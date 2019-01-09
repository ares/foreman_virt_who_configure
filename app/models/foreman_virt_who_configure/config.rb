module ForemanVirtWhoConfigure
  class Config < ActiveRecord::Base
    PERMITTED_PARAMS = [
      :interval, :organization_id, :compute_resource_id, :whitelist, :blacklist, :hypervisor_id,
      :hypervisor_type, :hypervisor_server, :hypervisor_username, :hypervisor_password, :debug,
      :satellite_url, :proxy, :no_proxy, :name,
      # API parameter filtering_mode gets translated to listing_mode in the controller
      # We keep both params permitted for compatibility with 1.11
      :listing_mode, :filtering_mode, :filter_host_parents, :exclude_host_parents, :kubeconfig_path
    ]
    audited :except => [ :hypervisor_password, :last_report_at, :out_of_date_at ], :associations => []
    include Authorizable
    validates_lengths_from_database

    UNLIMITED = 0
    WHITELIST = 1
    BLACKLIST = 2
    FILTERING_MODES = {
      UNLIMITED.to_s => N_('Unlimited'),
      WHITELIST.to_s => N_('Whitelist'),
      BLACKLIST.to_s => N_('Blacklist'),
    }

    WIZARD_STEPS = {
      'general_information' => N_('General information'),
      'schedule' => N_('Schedule'),
      'connection' => N_('Connection')
    }

    HYPERVISOR_IDS = [ 'hostname', 'uuid', 'hwuuid' ]

    HYPERVISOR_TYPES = {
      'esx' => 'VMware vSphere / vCenter (esx)',
      'rhevm' => 'Red Hat Virtualization Hypervisor (rhevm)',
      # 'vdsm' => 'Red Hat Enterprise Linux Hypervisor (vdsm)',
      'hyperv' => 'Microsoft Hyper-V (hyperv)',
      'xen' => 'XenServer (xen)',
      'libvirt' => 'libvirt',
      'kubevirt' => 'Container-native virtualization'
    }

    HYPERVISOR_DEFAULT_TYPE = 'esx'

    AVAILABLE_INTERVALS = {
      '60' => N_('Every hour'),
      '120' => N_('Every 2 hours'),
      '240' => N_('Every 4 hours'),
      '480' => N_('Every 8 hours'),
      '720' => N_('Every 12 hours'),
      '1440' => N_('Every 24 hours'),
      '2880' => N_('Every 2 days'),
      '4320' => N_('Every 3 days'),
    }

    DEFAULT_INTERVAL = 120

    STATUSES = {
      'ok' => N_('OK'),
      'out_of_date' => N_('No change'),
      'unknown' => N_('Unknown')
    }

    STATUS_DESCRIPTIONS = Hash.new(N_('Unknown configuration status, caused by unexpected conditions')).merge(
      {
        :unknown => N_('The configuration was not deployed yet or the virt-who was unable to report the status'),
        :ok => N_('The virt-who report arrived within the interval'),
        :out_of_date => N_('The virt-who report has not arrived within the interval, which indicates there was no change on hypervisor')
      }
    )

    include Encryptable
    encrypts :hypervisor_password

    belongs_to :compute_resource
    belongs_to :organization

    # service user used by virt-who to report back
    belongs_to :service_user

    scoped_search :on => :interval, :complete_value => true
    scoped_search :on => :name
    scoped_search :on => :status, :complete_value => true, :only_explicit => true, :operators => ['= '], :ext_method => :search_by_status
    scoped_search :on => :out_of_date_at, :complete_value => true, :only_explicit => true
    scoped_search :on => :last_report_at, :complete_value => true, :only_explicit => true
    # TODO add more related objects and attributes

    # compatibility layer for 1.11 - pre strong params patch
    if self.respond_to?(:attr_accessible)
      attr_accessible(*PERMITTED_PARAMS)
    end

    after_create :create_service_user
    after_destroy :destroy_service_user

    validates :interval, :hypervisor_type, :hypervisor_server,
              :satellite_url, :hypervisor_id, :organization_id, :name,
              :presence => true
    validates :name, :uniqueness => { :scope => :organization_id }
    validates :hypervisor_password, :presence => true, :if => Proc.new { |c| c.hypervisor_type != 'libvirt' && c.hypervisor_type != 'kubevirt' }
    validates :hypervisor_username, :presence => true, :if => Proc.new { |c| c.hypervisor_type != 'kubevirt' }
    validates :hypervisor_type, :inclusion => HYPERVISOR_TYPES.keys
    validates :hypervisor_id, :inclusion => HYPERVISOR_IDS
    validates :interval, :inclusion => AVAILABLE_INTERVALS.keys.map(&:to_i)
    validates :listing_mode, :inclusion => FILTERING_MODES.keys.map(&:to_i)
    validate :validates_whitelist_blacklist

    def validates_whitelist_blacklist
      case listing_mode.to_i
        when WHITELIST
          unless whitelist.present? || filter_host_parents.present?
            [:whitelist, :filter_host_parents].each {|f| errors.add(f, "Filter hosts or Filter host parents is required")}
          end
        when BLACKLIST
          unless blacklist.present? || exclude_host_parents.present?
            [:blacklist, :exclude_host_parents].each {|f| errors.add(f, "Exclude hosts or Exclude host parents is required")}
          end
      end
    end

    validates_lengths_from_database

    before_validation :remove_whitespaces

    scope :out_of_date, ->(deadline = DateTime.now.utc) { where(["out_of_date_at < ?", deadline.utc.to_s(:db)]) }
    scope :for_organization, ->(org) { org.nil? ? where(nil) : where(:organization_id => org) }

    def self.search_by_status(key, operator, value)
      condition = case value
                    when 'ok'
                      sanitize_sql_for_conditions([' out_of_date_at >= ? ', DateTime.now.utc.to_s(:db)])
                    when 'unknown'
                      sanitize_sql_for_conditions([' last_report_at IS NULL'])
                    when 'out_of_date'
                      sanitize_sql_for_conditions([' out_of_date_at < ? ', DateTime.now.utc.to_s(:db)])
                  end
      { :conditions => condition }
    end

    def permission_name(action)
      case action
        when :create
          'create_virt_who_config'
        when :edit
          'edit_virt_who_config'
        else
          raise "unknown permission for action #{action}"
      end
    end

    def create_service_user
      User.skip_permission_check do
        password = User.random_password
        service_user = self.build_service_user
        user = service_user.build_user
        user.auth_source = AuthSourceHiddenWithAuthentication.default
        user.password = password
        user.login = "virt_who_reporter_#{self.id}"
        user.organizations = [self.organization]
        user.roles = [Role.where(:name => 'Virt-who Reporter').first]
        user.valid? # to trigger password hashing
        user.save!(:validate => false)

        service_user.encrypted_password = password
        service_user.save!

        self.update_attribute :service_user_id, service_user.id
      end
    end

    def destroy_service_user
      User.skip_permission_check do
        # skip validation that prevents hidden user deletion
        user = User.unscoped.find_by_id(service_user.user_id)
        service_user.destroy
        user.delete
      end
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

    def humanized_interval
      _("every %s hours") % (self.interval / 60)
    end

    def out_of_date?(deadline = DateTime.now.utc)
      self.out_of_date_at.present? && self.out_of_date_at < deadline
    end

    def step_name(step_key)
      _(WIZARD_STEPS[step_key])
    end

    def steps
      WIZARD_STEPS.keys
    end

    def virt_who_bash_script
      virt_who_config_script(:bash_script)
    end

    def virt_who_config_script(format = nil)
      generator = OutputGenerator.new(self)
      if generator.ready_for_virt_who_output?
        generator.virt_who_output(format)
      else
        generator.missing_virt_who_input_messages.join("\n")
      end
    end

    def virt_who_config_command
      "hammer virt-who-config deploy --id #{self.id} --organization-id #{self.organization_id}"
    end

    def virt_who_touch!
      self.last_report_at = DateTime.now.utc
      self.out_of_date_at = self.last_report_at + self.interval.minutes
      self.class.skip_permission_check { self.save! }
    end

    def status
      case
        when self.last_report_at.nil?
          :unknown
        when !self.out_of_date?
          :ok
        else
          # out of date is currently considered ok too, virt-who does not send any report if there's no change on hypervisor
          :out_of_date
      end
    end

    def status_description
      _(STATUS_DESCRIPTIONS[status])
    end

    private

    def remove_whitespaces
      satellite_url.strip! if satellite_url.present?
    end
  end
end
