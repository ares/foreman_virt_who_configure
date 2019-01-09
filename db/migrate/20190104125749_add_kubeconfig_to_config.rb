class AddKubeconfigToConfig < ActiveRecord::Migration[4.2]
  def change
    add_column :foreman_virt_who_configure_configs, :kubeconfig_path, :string, :null => true
  end
end
