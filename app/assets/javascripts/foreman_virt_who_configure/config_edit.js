function virt_who_update_listing_mode() {
  var filtering_mode = $('#foreman_virt_who_configure_config_listing_mode').val();
  var whitelist = $('#foreman_virt_who_configure_config_whitelist').parents('div.form-group');
  var blacklist = $('#foreman_virt_who_configure_config_blacklist').parents('div.form-group');
  var whitelist_parent = $('#foreman_virt_who_configure_config_filter_host_parents').parents('div.form-group');
  var blacklist_parent = $('#foreman_virt_who_configure_config_exclude_host_parents').parents('div.form-group');

  // UNLIMITED = 0, WHITELIST = 1, BLACKLIST = 2, see config.rb model for the definition
  if (filtering_mode == '0') {
    whitelist.hide();
    blacklist.hide();
    whitelist_parent.hide();
    blacklist_parent.hide();
  } else if (filtering_mode == '1') {
    whitelist.show();
    whitelist_parent.show();
    blacklist.hide();
    blacklist_parent.hide();
  } else if (filtering_mode == '2') {
    whitelist.hide();
    whitelist_parent.hide();
    blacklist.show();
    blacklist_parent.show();
  }
}

function virt_who_update_hypervisor_fields() {
  selected_type = $('#foreman_virt_who_configure_config_hypervisor_type').val();
  var element = $('#foreman_virt_who_configure_config_hypervisor_username');
  element.closest('.form-group').toggle(selected_type != 'kubevirt');
  var element = $('#foreman_virt_who_configure_config_hypervisor_password');
  element.closest('.form-group').toggle(selected_type != 'libvirt' && selected_type != 'kubevirt');
  var element = $('#foreman_virt_who_configure_config_kubeconfig_path');
  element.closest('.form-group').toggle(selected_type == 'kubevirt');
}

function virt_who_update_credentials_help() {
  selected_type = $(this).val();
  $.each(['hypervisor_server', 'hypervisor_username'], function(index, value) {
    var element = $('#foreman_virt_who_configure_config_' + value);
    var help = element.data("help")[selected_type];
    var inline_help_popover = element.parents('.form-group').find('.help-inline a[rel=popover]');
    if (inline_help_popover[0]) {
      // pre Foreman 1.15
      inline_help_popover.attr('data-content', help);
    } else {
      element.parents('.form-group').find('label a[rel=popover]').attr('data-content', help);
    }
  });
}

$(document).ready(function () {
  virt_who_update_listing_mode();
  virt_who_update_hypervisor_fields();
  $('#foreman_virt_who_configure_config_listing_mode').change(virt_who_update_listing_mode);
  $('#foreman_virt_who_configure_config_hypervisor_type').change(virt_who_update_credentials_help);
  $('#foreman_virt_who_configure_config_hypervisor_type').change(virt_who_update_hypervisor_fields);
});
