module ForemanVirtWhoConfigure
  module ConfigsHelper
    def hypervisor_server_help_data
      @hypervisor_server_help_data ||= {
        'esx' => _('VMware vCenter server’s fully qualified host name or IP address.'),
        'rhevm' => _('Red Hat Virtualization Manager’s fully qualified host name or IP address. For example, <code>https://hostname:443/ovirt-engine/</code> for v4, <code>https://hostname_or_IP:443</code> for v3'),
        # 'vdsm' => 'Red Hat Enterprise Linux Hypervisor (vdsm)',
        'hyperv' => _('Microsoft Hyper-V fully qualified host name or IP address.'),
        'xen' => _('XenServer server’s fully qualified host name or IP address.'),
        'libvirt' => _('Libvirt server’s fully qualified host name or IP address. You can also specify preferred schema, for example: <code>qemu+ssh://libvirt.example.com/system</code>. If you use SSH, make sure you setup root\'s SSH key on target host for a user specified at hypervisor username field'),
        'kubevirt' => _('Container-native virtualization’s fully qualified host name or IP address. In order to connect to the cluster it is required to provide path to kubeconfig which contains connection details and authentication token.')
      }
    end

    def hypervisor_username_help_data
      @hypervisor_username_help_data ||= {
        'esx' => _('Account name by which virt-who is to connect to the hypervisor, in the format <code>domain_name\account_name</code>. Note that only a single backslash separates the values for domain_name and account_name. If you are using a domain account, and the global configuration file <code>/etc/sysconfig/virt-who</code>, then <b>two</b> backslashes are required. For further details, see <a href="https://access.redhat.com/solutions/1270223">Red Hat Knowledgebase solution How to use a windows domain account with virt-who</a> for more information.'),
        'rhevm' => _('Account name by which virt-who is to connect to the Red Hat Enterprise Virtualization Manager instance. The username option requires input in the format username@domain.'),
        # 'vdsm' => '',
        'hyperv' => _('Account name by which virt-who is to connect to the hypervisor. By default this is <code>Administrator</code>. To use an alternate account, create a user account and assign that account to the following groups (Windows 2012 Server): Hyper-V Administrators and Remote Management Users.'),
        'xen' => _('Account name by which virt-who is to connect to the hypervisor.'),
        'libvirt' => _('Account name by which virt-who is to connect to the hypervisor. Virt-who does not support password based authentication, you must manually setup SSH key, see <a href="https://access.redhat.com/solutions/1515983">Red Hat Knowledgebase solution How to configure virt-who for a KVM host</a> for more information.'),
        'kubevirt' => ''
      }
    end

    def config_report_status(config)
      message = case config.status
                  when :unknown
                    _('No Report Yet')
                  when :ok, :out_of_date
                    l(config.last_report_at, :format => :long)
                  else
                    _('Unknown configuration status')
                end

      config_report_status_icon(config) + content_tag(:span, message, :class => config.status)
    end

    def config_report_status_icon(config)
      content_tag(:span, ''.html_safe, :class => report_status_class(config.status), :title => config.status_description) + '&nbsp;'.html_safe
    end

    def report_status_class(status)
      icon_class = case status
                     when :ok, :out_of_date
                       'pficon-ok'
                     when :unknown
                       'pficon-info'
                     else
                       'pficon-help'
                   end

      "virt-who-config-report-status #{icon_class} #{status_class(status)}"
    end

    def status_class(status)
      case status
        when :ok, :out_of_date
          'status-ok'.html_safe
        when :unknown
          'status-info'.html_safe
        else
          'status-warn'.html_safe
      end
    end

    def config_attribute_default_label(attr)
      s_(ForemanVirtWhoConfigure::Config.gettext_translation_for_attribute_name(attr)).titleize
    end

    def config_attribute_label(attr, label)
      content_tag :div, :class => 'col-md-2' do
        content_tag :strong, (label || config_attribute_default_label(attr))
      end
    end

    def config_attribute_value(attribute, value)
      content_tag :div, :class => 'config-status' do
        content_tag :span, value, :class => "config-#{attribute}"
      end
    end

    def config_attribute(attribute, value, label = nil)
      content_tag :div, :class => 'row' do
        config_attribute_label(attribute, label) + config_attribute_value(attribute, value)
      end
    end
  end
end
