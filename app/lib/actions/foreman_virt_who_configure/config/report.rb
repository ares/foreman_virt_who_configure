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
          require 'pry-remote'
          binding.remote_pry
          input['hypervisors'].each do |hv_attrs|
            # should always exist, Actions::Katello::Host::HypervisorsUpdate should create it
            # but we should be careful anyway
            hypervisor = ::Katello::Host::SubscriptionFacet.find_by_uuid(hv_attrs['uuid'])
            hypervisor = ::Host.joins(:subscription_facet).where(:'katello_subscription_facets.uuid' => hv_attrs['uuid']).first
          end
          config = ::ForemanVirtWhoConfigure::ServiceUser.find_by_user_id(User.current.id).try(:config)
          if config.present?
            config.hypervisor_server # this is the entry point for compute resource
            config.touch(:last_report_at)
          end

          # todo create a custom status for the host
          # todo log when there was an incoming report from another config
        end
      end
    end
  end
end
