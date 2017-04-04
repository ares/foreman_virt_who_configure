module ForemanVirtWhoConfigure
  module Concerns
    module ReportLogger
      extend ActiveSupport::Concern

      included do
        before_action :log_incoming_report, :only => [ :hypervisors_update ]
        # after_action :parse_task, :only => [ :hypervisors_update ]
      end

      def log_incoming_report
        # TODO might not find config, should trigger, we should keep the info though
        hypervisor_ids = params.keys # probably not interesting at the moment, we should keep it to find duplicates
        config = ForemanVirtWhoConfigure::ServiceUser.find_by_user_id(User.current.id).try(:config)
        if config.present?
          config.hypervisor_server # this is the entry point for compute resource
          config.touch(:last_report_at)
        end
        # we could link existing content-hosts (or hosts) with this configuration so we can show reporting status for them
      end

      def parse_task
        # can't access the task from there :-/
        # require 'pry-remote'
        # binding.pry_remote
      end
    end
  end
end
