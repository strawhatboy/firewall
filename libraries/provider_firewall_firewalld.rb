#
# Author:: Ronald Doorn (<rdoorn@schubergphilis.com>)
# Cookbook Name:: firewall
# Resource:: default
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
class Chef
  class Provider::FirewallFirewalld < Chef::Provider::LWRPBase
    include FirewallCookbook::Helpers::Firewalld

    provides :firewall, os: 'linux', platform_family: %w(rhel fedora) do |node|
      node['platform_version'].to_f >= 7.0
    end

    def whyrun_supported?
      false
    end

    action :install do
      next if disabled?(new_resource)

      converge_by('install firewalld, create template for /etc/sysconfig') do
        package 'firewalld' do
          action :install
        end

        service 'firewalld' do
          action [:enable, :start]
        end

        file "create empty #{firewalld_rules_filename}" do
          path firewalld_rules_filename
          content '# created by chef to allow service to start'
          not_if { ::File.exist?(firewalld_rules_filename) }
        end
      end
    end

    action :restart do
      next if disabled?(new_resource)

      # ensure it's initialized
      new_resource.rules({}) unless new_resource.rules
      new_resource.rules['firewalld'] = {} unless new_resource.rules['firewalld']

      # ensure a file resource exists with the current firewalld rules
      begin
        firewalld_file = run_context.resource_collection.find(file: firewalld_rules_filename)
      rescue
        firewalld_file = file firewalld_rules_filename do
          action :nothing
        end
      end
      firewalld_file.content build_rule_file(new_resource.rules['firewalld'])
      firewalld_file.run_action(:create)

      # ensure the service is running
      service 'firewalld' do
        action [:enable, :start]
      end

      # mark updated if we changed the zone
      unless firewalld_default_zone?(new_resource.enabled_zone)
        firewalld_default_zone!(new_resource.enabled_zone)
        new_resource.updated_by_last_action(true)
      end

      # if the file was changed, load new ruleset
      if firewalld_file.updated_by_last_action?
        firewalld_flush!
        # TODO: support logging

        new_resource.rules['firewalld'].sort_by { |_k, v| v }.map { |k, _v| k }.each do |cmd|
          firewalld_rule!(cmd)
        end

        new_resource.updated_by_last_action(true)
      end
    end

    action :disable do
      next if disabled?(new_resource)

      firewalld_flush!
      firewalld_default_zone!(new_resource.disabled_zone)
      new_resource.updated_by_last_action(true)

      service 'firewalld' do
        action [:disable, :stop]
      end

      file "create empty #{firewalld_rules_filename}" do
        path firewalld_rules_filename
        content '# created by chef to allow service to start'
        action :create
      end
    end

    action :flush do
      next if disabled?(new_resource)

      firewalld_flush!
      new_resource.updated_by_last_action(true)

      file "create empty #{firewalld_rules_filename}" do
        path firewalld_rules_filename
        content '# created by chef to allow service to start'
        action :create
      end
    end

    action :save do
      next if disabled?(new_resource)

      unless firewalld_all_rules_permanent!
        firewalld_save!
        new_resource.updated_by_last_action(true)
      end
    end
  end
end
