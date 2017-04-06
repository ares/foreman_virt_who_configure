class AddLastReportInfoToConfig < ActiveRecord::Migration
  def change
    add_column :foreman_virt_who_configure_configs, :last_report_at, :datetime
    add_column :foreman_virt_who_configure_configs, :expires_at, :datetime
  end
end
