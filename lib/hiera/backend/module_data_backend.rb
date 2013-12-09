class Hiera
  module Backend
    class Module_data_backend
      def initialize(cache=nil)
        require 'yaml'
        require 'hiera/filecache'

        Hiera.debug("Hiera Module Data backend starting")

        @cache = cache || Filecache.new
      end

      def load_module_config(module_name, environment)
        path = nil
        default_config = {:hierarchy => ["common"]}
        env = Puppet::Node::Environment.new(environment)

        if not module_name
          path = File::dirname(env['manifest'])
        elsif mod = env.module(module_name)
          path = mod.path
        end

        if path
          module_config = File.join(path, "data", "hiera.yaml")
          config = {}

          if File.exist?(module_config)
            Hiera.debug("Reading config from %s file" % module_config)
            config = load_data(module_config)
          end

          config["path"] = path

          return default_config.merge(config)
        else
          return default_config
        end
      end

      def load_data(path)
        return {} unless File.exist?(path)

        @cache.read(path, Hash, {}) do |data|
          YAML.load(data)
        end
      end

      def lookup(key, scope, order_override, resolution_type)
        answer = nil

        Hiera.debug("Looking up %s in Module Data backend" % key)

        [nil, scope["module_name"]].each do |module_name|
          config = load_module_config(module_name, scope["environment"])

          unless config["path"]
            Hiera.debug("Could not find a path to the module '%s' in environment '%s'" % [module_name, scope["environment"]])
            next
          end

          module_answer = nil

          config[:hierarchy].each do |source|
            source = File.join(config["path"], "data", "%s.yaml" % Backend.parse_string(source, scope))

            Hiera.debug("Looking for data in source %s" % source)
            data = load_data(source)

            raise("Data loaded from %s should be a hash but got %s" % [source, data.class]) unless data.is_a?(Hash)

            next if data.empty?
            next unless data.include?(key)

            module_answer = merge_answer(module_answer, data[key], scope, resolution_type)
            return module_answer unless [:array, :hash].include?(resolution_type)
          end

          next unless module_answer

          answer = merge_answer(answer, module_answer, scope, resolution_type)
        end

        return answer
      end

      def merge_answer(answer, found, scope, resolution_type)
        case resolution_type
          when :array
            raise("Hiera type mismatch: expected Array or String and got %s" % found.class) unless [Array, String].include?(found.class)
            answer ||= []
            answer << Backend.parse_answer(found, scope)

          when :hash
            raise("Hiera type mismatch: expected Hash and got %s" % found.class) unless found.is_a?(Hash)
            answer ||= {}
            answer = found.merge(answer)

          else
            answer = Backend.parse_answer(found, scope)
        end

        return answer
      end
    end
  end
end
