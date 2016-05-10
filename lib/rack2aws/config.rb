require 'rack2aws/props_reader'
require 'rack2aws/errors'

# Class to parse configuration files in the format of "param = value".
class KVConfigParser
  attr_accessor :config_file, :params, :groups

  # Initialize the class with the path to the 'config_fil'
  # The class objects are dynamically generated by the
  # name of the 'param' in the config file.  Therefore, if
  # the config file is 'param = value' then the itializer
  # will eval "@param = value"
  #
  def initialize(config_file=nil, separator = '=')
    @config_file = config_file
    @params = {}
    @groups = []
    @splitRegex = '\s*' + separator + '\s*'

    if(self.config_file)
      self.validate_config()
      self.import_config()
    end
  end

  # Validate the config file, and contents
  def validate_config()
    unless File.readable?(self.config_file)
      raise Errno::EACCES, "#{self.config_file} is not readable"
    end
    # FIX ME: need to validate contents/structure?
  end

  # Import data from the config to our config object.
  def import_config()
    # The config is top down.. anything after a [group] gets added as part
    # of that group until a new [group] is found.
    group = nil
    open(self.config_file) {
      |f|
      f.each_with_index do |line, i|
        line.strip!
        # force_encoding not available in all versions of ruby
        begin
          if i.eql? 0 and line.include?("\xef\xbb\xbf".force_encoding("UTF-8"))
            line.delete!("\xef\xbb\xbf".force_encoding("UTF-8"))
          end
        rescue NoMethodError
        end

        unless (/^\#/.match(line))
          if(/#{@splitRegex}/.match(line))
            param, value = line.split(/#{@splitRegex}/, 2)
            var_name = "#{param}".chomp.strip
            value = value.chomp.strip
            new_value = ''
            if (value)
              if value =~ /^['"](.*)['"]$/
                new_value = $1
              else
                new_value = value
              end
            else
              new_value = ''
            end

            if group
              self.add_to_group(group, var_name, new_value)
            else
              self.add(var_name, new_value)
            end

          elsif(/^\[(.+)\]$/.match(line).to_a != [])
            group = /^\[(.+)\]$/.match(line).to_a[1]
            self.add(group, {})
          end
        end
      end
    }
  end

  # This method will provide the value held by the object "@param"
  # where "@param" is actually the name of the param in the config
  # file.
  #
  # DEPRECATED - will be removed in future versions
  #
  def get_value(param)
    puts "ParseConfig Deprecation Warning: get_value() is deprecated. Use " + \
         "config['param'] or config['group']['param'] instead."
    return self.params[param]
  end

  # This method is a shortcut to accessing the @params variable
  def [](param)
    return self.params[param]
  end

  # This method returns all parameters/groups defined in a config file.
  def get_params()
    return self.params.keys
  end

  # List available sub-groups of the config.
  def get_groups()
    return self.groups
  end

  # Adds an element to the config object
  def add(param_name, value, override = false)
    if value.class == Hash
      if self.params.has_key?(param_name)
        if self.params[param_name].class == Hash
          if override
            self.params[param_name] = value
          else
            self.params[param_name].merge!(value)
          end
        elsif self.params.has_key?(param_name)
          if self.params[param_name].class != value.class
            raise ArgumentError, "#{param_name} already exists, and is of different type!"
          end
        end
      else
        self.params[param_name] = value
      end
      if ! self.groups.include?(param_name)
        self.groups.push(param_name)
      end
    else
      self.params[param_name] = value
    end
  end

  # Add parameters to a group. Parameters with the same name
  # could be placed in different groups
  def add_to_group(group, param_name, value)
    if ! self.groups.include?(group)
      self.add(group, {})
    end
    self.params[group][param_name] = value
  end
end


module Rack2Aws
  module Configuration

    class RackspaceConfig
      def self.load()
        @config_path ||= "#{ENV['HOME']}/.rack/config"

        if !File.exist?(@config_path)
          raise FileNotFoundError, "Rackspace configuration file not found"
        end

        props_reader = PropertiesReader.new(@config_path)
        return {
          :provider => 'Rackspace',
          :rackspace_api_key => props_reader.get("api-key"),
          :rackspace_username => props_reader.get("username"),
          :rackspace_region => props_reader.get("region")
        }
      end
    end

    class AWSConfig
      def self.load()
        @config_path ||= "#{ENV['HOME']}/.aws/credentials"

        if !File.exist?(@config_path)
          raise FileNotFoundError, "AWS configuration file not found"
        end

        credentials = KVConfigParser.new(@config_path)
        return {
          :provider => 'AWS',
          :region => credentials['default']['region'],
          :aws_access_key_id => credentials['default']['aws_access_key_id'],
          :aws_secret_access_key => credentials['default']['aws_secret_access_key']
        }
      end
    end

  end
end
