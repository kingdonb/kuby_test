require 'active_support/core_ext'
require 'active_support/encrypted_configuration'

# Define a production Kuby deploy environment
Kuby.define('KubyTest') do
  environment(:production) do
    # Because the Rails environment isn't always loaded when
    # your Kuby config is loaded, provide access to Rails
    # credentials manually.
    app_creds = ActiveSupport::EncryptedConfiguration.new(
      config_path: File.join('config', 'credentials.yml.enc'),
      key_path: File.join('config', 'master.key'),
      env_key: 'RAILS_MASTER_KEY',
      raise_if_missing_key: true
    )

    docker do
      credentials do
        username app_creds[:KUBY_DOCKER_USERNAME]
        password ENV['CR_PAT']
        email app_creds[:KUBY_DOCKER_EMAIL]
      end

      image_url 'ghcr.io/kingdonb/kuby-tester'
    end

    kubernetes do
      provider :bare_metal

      # Add a plugin that facilitates deploying a Rails app.
      add_plugin :rails_app do
        hostname 'kuby-test.hephy.pro'

        manage_database false
        ingress_class 'traefik'
      end
    end
  end
end
