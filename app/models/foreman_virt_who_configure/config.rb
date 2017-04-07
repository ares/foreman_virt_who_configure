module ForemanVirtWhoConfigure
  class Config < ActiveRecord::Base
    PERMITTED_PARAMS = [
      :interval, :organization_id, :compute_resource_id, :whitelist, :blacklist, :listing_mode, :hypervisor_id,
      :hypervisor_type, :hypervisor_server, :hypervisor_username, :hypervisor_password, :debug,
      :satellite_url, :proxy, :no_proxy
    ]
    include Authorizable
    audited
    validates_lengths_from_database

    UNLIMITED = 0
    WHITELIST = 1
    BLACKLIST = 2
    FILTERING_MODES = {
      UNLIMITED.to_s => _('Unlimited'),
      WHITELIST.to_s => _('Whitelist'),
      BLACKLIST.to_s => _('Blacklist'),
    }

    WIZARD_STEPS = {
      'general_information' => _('General information'),
      'schedule' => _('Schedule'),
      'connection' => _('Connection')
    }

    HYPERVISOR_IDS = [ 'hostname', 'uuid', 'hwuuid' ]

    HYPERVISOR_TYPES = {
      'esx' => 'VMware vSphere / vCenter (esx)',
      'rhevm' => 'Red Hat Virtualization Hypervisor (rhevm)',
      # 'vdsm' => 'Red Hat Enterprise Linux Hypervisor (vdsm)',
      'hyperv' => 'Microsoft Hyper-V (hyperv)',
      'xen' => 'XenServer (xen)',
      'libvirt' => 'libvirt'
    }

    HYPERVISOR_DEFAULT_TYPE = 'esx'

    AVAILABLE_INTERVALS = {
      '60' => _('Every hour'),
      '120' => _('Every 2 hours'),
      '240' => _('Every 4 hours'),
      '480' => _('Every 8 hours'),
      '720' => _('Every 12 hours'),
    }

    DEFAULT_INTERVAL = 120

    STATUSES = {
      'ok' => _('OK'),
      'error' => _('Error'),
      'unknown' => _('Unknown')
    }

    STATUS_DESCRIPTIONS = Hash.new(_('Unknown configuration status, caused by unexpected conditions')).merge(
      {
        :unknown => _('The configuration was not deployed yet or the virt-who was unable to report the status'),
        :ok => _('The virt-who report arrived within the interval'),
        :error => _('The virt-who report has not arrived within the interval, please check the virt-who reporter status and logs')
      }
    )

    include Encryptable
    encrypts :hypervisor_password

    belongs_to :compute_resource
    belongs_to :organization

    # service user used by virt-who to report back
    belongs_to :service_user

    scoped_search :on => :interval, :complete_value => true
    scoped_search :on => :status, :complete_value => true, :only_explicit => true, :operators => ['= '], :ext_method => :search_by_status
    scoped_search :on => :expires_at, :complete_value => true, :only_explicit => true
    scoped_search :on => :last_report_at, :complete_value => true, :only_explicit => true
    # TODO add more related objects and attributes

    # compatibility layer for 1.11 - pre strong params patch
    if self.respond_to?(:attr_accessible)
      attr_accessible(*PERMITTED_PARAMS)
    end

    after_create :create_service_user
    after_destroy :destroy_service_user

    validates :interval, :hypervisor_type, :hypervisor_server, :hypervisor_username, :hypervisor_password,
              :satellite_url, :hypervisor_id, :organization_id,
              :presence => true
    validates :hypervisor_type, :inclusion => HYPERVISOR_TYPES.keys
    validates :hypervisor_id, :inclusion => HYPERVISOR_IDS
    validates :interval, :inclusion => AVAILABLE_INTERVALS.keys.map(&:to_i)
    validates :listing_mode, :inclusion => FILTERING_MODES.keys.map(&:to_i)
    validates :whitelist, :presence => true, :if => Proc.new { |c| c.listing_mode.to_i == WHITELIST }
    validates :blacklist, :presence => true, :if => Proc.new { |c| c.listing_mode.to_i == BLACKLIST }
    validates_lengths_from_database

    before_validation :remove_whitespaces

    scope :expired, ->(deadline = DateTime.now) { where(["expires_at < ?", deadline.to_s(:db)]) }
    scope :for_organization, ->(org) { org.nil? ? where(nil) : where(:organization_id => org) }

    def self.search_by_status(key, operator, value)
      condition = case value
        when 'ok'
          sanitize_sql_for_conditions([' expires_at >= ? ', DateTime.now.to_s(:db)])
        when 'unknown'
          sanitize_sql_for_conditions({ :last_report_at => nil })
        when 'error'
          sanitize_sql_for_conditions([' expires_at < ? ', DateTime.now.to_s(:db)])
      end
      { :conditions => condition }
    end

    def create_service_user
      password = User.random_password
      service_user = self.build_service_user
      user = service_user.build_user
      user.auth_source = AuthSourceHiddenWithAuthentication.default
      user.password = password
      user.login = "virt_who_reporter_#{self.id}"
      user.organizations = [ self.organization ]
      user.roles = [ Role.where(:name => 'Virt-who Reporter').first ]
      user.valid? # to trigger password hashing
      user.save!(:validate => false)

      service_user.encrypted_password = password
      service_user.save!

      self.update_attribute :service_user_id, service_user.id
    end

    def destroy_service_user
      # skip validation that prevents hidden user deletion
      user = service_user.user
      service_user.destroy
      user.delete
    end

    # mapping of supported CR types
    # case config.compute_resource
    #   when Foreman::Model::Libvirt
    #     'libvirt'
    #   when Foreman::Model::Vmware
    #     'esx'
    #   when Foreman::Model::Ovirt
    #     'rhevm'
    #   else
    #     raise 'unsupported compute resource type'
    # end

    # Foreman 1.11 specifics, can be removed later, otherwise when string does not start with "encrypts" prefix
    # we get 500 when we try to create log message that relies on name method
    def name
      title
    end

    def title
      compute_resource ? compute_resource.name : hypervisor_server
    end

    def humanized_interval
      _("every %s hours") % (self.interval / 60)
    end

    def expired?(deadline = DateTime.now)
      self.expires_at < deadline
    end

    def step_name(step_key)
      WIZARD_STEPS[step_key]
    end

    def steps
      WIZARD_STEPS.keys
    end

    def virt_who_config_file
      generator = OutputGenerator.new(self)
      if generator.ready_for_virt_who_output?
        generator.virt_who_output
      else
        generator.missing_virt_who_input_messages.join("\n")
      end
    end

    def virt_who_touch!
      self.last_report_at = DateTime.now
      self.expires_at = self.last_report_at + self.interval.minutes
      self.save!
    end

    def status
      case
        when self.last_report_at.nil?
          :unknown
        when !self.expired?
          :ok
        else
          :error
      end
    end

    def status_description
      STATUS_DESCRIPTIONS[status]
    end

    private

    def remove_whitespaces
      satellite_url.strip! if satellite_url.present?
    end
  end
end
