class AddLastReportToConfig < ActiveRecord::Migration
  def change
    add_column :foreman_virt_who_configure_configs, :last_report_at, :datetime
  end
end
