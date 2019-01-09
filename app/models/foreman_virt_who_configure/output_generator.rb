require 'shellwords'

module ForemanVirtWhoConfigure
  class OutputGenerator
    class ConfigurationResult
      attr_reader :code, :identifier, :message
      def initialize(code, identifier, message)
        @code, @message, @identifier = code, message, identifier
      end
    end

    MINIMUM_VIRT_WHO_VERSION = '0.24.2'

    LIBVIRT_FAKE_PASSWORD = 'libvirt_fake_password'

    CONFIGURATION_RESULTS = [
      ConfigurationResult.new(0, 'success', N_('Success')),
      ConfigurationResult.new(1, 'virt_who_too_old', N_('Newer version of virt-who is required, minimum version is %s') % MINIMUM_VIRT_WHO_VERSION),
      ConfigurationResult.new(2, 'virt_who_config_file_issue', N_('Unable to create virt-who config file')),
      ConfigurationResult.new(4, 'virt_who_sysconfig_file_issue', N_('Unable to create sysconfig file')),
      ConfigurationResult.new(8, 'virt_who_chkconfig_issue', N_('Unable to enable virt-who service using chkconfig')),
      ConfigurationResult.new(16, 'virt_who_service_issue', N_('Unable to start virt-who service, please see virt-who logs for more details')),
      ConfigurationResult.new(32, 'virt_who_installation', N_('Unable to install virt-who package, make sure the host is properly subscribed and has access to satellite-tools repository')),
    ]

    attr_reader :config

    def initialize(config)
      @config = config
    end

    def error_code(error_name)
      result = CONFIGURATION_RESULTS.find { |result| result.identifier == error_name.to_s }
      result.try(:code)
    end

    def ready_for_virt_who_output?
      missing_virt_who_input_messages.empty?
    end

    def missing_virt_who_input_messages
      messages = []
      messages.push _('Owner was not provided') unless config.organization_id?
      messages.push _('Interval was not provided') unless config.interval.present?
      # messages.push _('Cofiguration not stored') unless config.persisted?
      # messages.push _('Service user was not provided') unless config.service_user_id.present?
      messages
    end

    def virt_who_output(format = nil)
      kubeconfig = config.hypervisor_type == 'kubevirt' ? "\nkubeconfig=#{config.kubeconfig_path}" : ''
      result = ''
      result += "#!/bin/bash\n" if format == :bash_script
      result += <<EOS
heading() {
  echo -e "\\n== $1 =="
}

step() {
  step_count=5
  heading "[$1/$step_count] $2"
}

version_lte() {
  [ "$1" = "`echo -e "$1\\n$2" | sort -V | head -n1`" ]
}

version_lt() {
  [ "$1" = "$2" ] && return 1 || version_lte $1 $2
}

verify_minimal_version() {
  minimal_version=#{MINIMUM_VIRT_WHO_VERSION}
  installed_version=`rpm -q --queryformat '%{VERSION}' virt-who`

  if version_lt $installed_version $minimal_version; then
    echo "virt-who $installed_version does not meet minimum requirements, please make sure this host is properly subscribed and has access to satellite-tools repository, minimal virt-who version is $minimal_version"
    return 1
  else
    return 0
  fi
}

result_code=#{error_code(:success)}
step 1 "Installing virt-who"
yum install -y virt-who || result_code=$(($result_code|#{error_code(:virt_who_installation)}))

if verify_minimal_version; then
  step 2 "Encrypting password"
  cr_password=`virt-who-password --password '#{cr_password}' 2> /dev/null`
  user_password=`virt-who-password --password '#{service_user_password}' 2> /dev/null`

  step 3 "Creating virt-who configuration"
  cat > #{config_file_path} << EOF
### This configuration file is managed via the virt-who configure plugin
### manual edits will be deleted.
[#{identifier}]
type=#{type}
hypervisor_id=#{hypervisor_id}
owner=#{owner}
env=Library
server=#{cr_server}
username=#{cr_username}
encrypted_password=$cr_password#{filtering}
rhsm_hostname=#{satellite_url}
rhsm_username=#{service_user_username}
rhsm_encrypted_password=$user_password
rhsm_prefix=/rhsm#{kubeconfig}
EOF
  if [ $? -ne 0 ]; then result_code=$(($result_code|#{error_code(:virt_who_config_file_issue)})); fi

  step 4 "Creating sysconfig virt-who configuration"
  cat > #{sysconfig_file_path} << EOF
### This configuration file is managed via the virt-who configure plugin
### manual edits will be deleted.
VIRTWHO_SATELLITE6=1
VIRTWHO_DEBUG=#{config.debug? ? 1 : 0}
VIRTWHO_INTERVAL=#{config.interval * 60}#{proxy_strings}
EOF
  if [ $? -ne 0 ]; then result_code=$(($result_code|#{error_code(:virt_who_sysconfig_file_issue)})); fi

  step 5 "Enabling and restarting the virt-who service"
  chkconfig virt-who on || result_code=$(($result_code|#{error_code(:virt_who_chkconfig_issue)}))
  service virt-who restart || result_code=$(($result_code|#{error_code(:virt_who_service_issue)}))
else
  result_code=$(($result_code|#{error_code(:virt_who_too_old)}))
fi

heading "Finished"
if [ $result_code -ne 0 ]; then
  echo "There were some errors during configuration:"
  #{error_handling}
else
  echo "Finished successfully"
fi

EOS
      result += "exit $result_code\n" if format == :bash_script
      result
    end

    def error_handling
      CONFIGURATION_RESULTS.map do |result|
        "[ $(($result_code&#{result.code})) -ge 1 ] && echo '#{result.message}'"
      end.join("\n  ")
    end

    def filtering
      case config.listing_mode.to_i
      when ForemanVirtWhoConfigure::Config::UNLIMITED
        ''
      when ForemanVirtWhoConfigure::Config::WHITELIST
        enabled_filters({'filter_hosts' => config.whitelist, 'filter_host_parents' => config.filter_host_parents})
      when ForemanVirtWhoConfigure::Config::BLACKLIST
        enabled_filters({'exclude_hosts' => config.blacklist, 'exclude_host_parents' => config.exclude_host_parents})
      end
    end

    def enabled_filters(filter)
      filter.reject { |_, list| list.empty? }.map { |filter,list| filtering_line_sanitized(filter, list) }.join(',')
    end

    def filtering_line_sanitized(filter, list)
      "\n" + filter + '=' + sanitize_filter(list.to_s)
    end

    def sanitize_filter(list)
      sanitize(list)
    end

    def config_file_path
      "/etc/virt-who.d/#{identifier}.conf"
    end

    def sysconfig_file_path
      '/etc/sysconfig/virt-who'
    end

    def identifier
      "virt-who-config-#{config.id}"
    end

    def hypervisor_id
      config.hypervisor_id
    end

    def owner
      config.organization.label
    end

    def type
      config.hypervisor_type
    end

    # returns nil if url could not be parsed or is invalid, e.g. qemu:///system
    def cr_server
      config.hypervisor_server
    end

    def cr_username
      Shellwords.escape(config.hypervisor_username)
    end

    def cr_password
      config.hypervisor_type == 'libvirt' && config.hypervisor_password.blank? ? LIBVIRT_FAKE_PASSWORD : config.hypervisor_password
    end

    def satellite_url
      config.satellite_url
    end

    def service_user_username
      config.service_user.username
    end

    def service_user_password
      config.service_user.encrypted_password
    end

    def cr
      config.compute_resource
    end

    def proxy
      config.proxy
    end

    def no_proxy
      config.no_proxy
    end

    def sanitize_proxy(string)
      sanitize(string)
    end

    def proxy_strings
      output = ''
      output << "\nhttp_proxy=#{sanitize_proxy(proxy)}" if proxy.present?
      output << "\nNO_PROXY=#{sanitize_proxy(no_proxy)}" if no_proxy.present?
      output << "\nNO_PROXY=*" if !proxy.present? && !no_proxy.present?
      output
    end

    def sanitize(string)
      string.tr("\r\n", '').strip.chomp(",")
    end
  end
end
