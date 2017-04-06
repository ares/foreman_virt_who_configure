module Actions
  module ForemanVirtWhoConfigure
    module Config
      class Report < Actions::EntryAction
        middleware.use Actions::Middleware::KeepCurrentUser

        def self.subscribe
          Actions::Katello::Host::HypervisorsUpdate
        end

        def plan(hypervisors)
          plan_self(:hypervisors => hypervisors)
        end

        def run
          # this is how we could do mapping to hypervisor hosts based on UUID provided by candelpin
          # input['hypervisors'].each do |hv_attrs|
          #   # should always exist, Actions::Katello::Host::HypervisorsUpdate should create it
          #   # but we should be careful anyway
          #   hypervisor = ::Host.joins(:subscription_facet).where(:'katello_subscription_facets.uuid' => hv_attrs['uuid']).first
          # end

          config = ::ForemanVirtWhoConfigure::ServiceUser.find_by_user_id(User.current.id).try(:config)
          if config.present?
            config.virt_who_touch!(:last_report_at)
          end

          # if config was not found, the report is coming from unknown virt-who reporter, we could create a notification
          # that this plugin can be used for configuration

          # this could be used for mapping to existing compute resource
          # config.hypervisor_server
        end
      end
    end
  end
end
