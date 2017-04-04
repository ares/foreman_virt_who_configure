module ForemanVirtWhoConfigure
  # holds the encrypted password for internal user that can be deployed to virt who reporter
  class ServiceUser < ActiveRecord::Base
    include Authorizable
    include Encryptable
    encrypts :encrypted_password

    belongs_to :user
    has_one :config

    # Foreman 1.11 specifics, can be removed later, otherwise when string does not start with "encrypts" prefix
    # we get 500 when we try to create log message that relies on name method
    def name
      self.username || self.to_s
    end

    def username
      self.user.login if self.user
    end
  end
end
