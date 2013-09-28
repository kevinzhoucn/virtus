module Virtus

  # Class to build a Virtus module with it's own configuration
  #
  # This allows for individual Virtus modules to be included in
  # classes and not impacted by the global Virtus configuration,
  # which is implemented using Virtus::Configuration.
  #
  # @private
  class Builder

    # Return module
    #
    # @return [Module]
    #
    # @api private
    attr_reader :module

    # Return configuration
    #
    # @return [Configuration]
    #
    # @api private
    attr_reader :configuration

    # Builds a new Virtus module
    #
    # The block is passed to Virtus::Configuration
    #
    # @example
    #   ModuleBuilder.call do |config|
    #     # config settings
    #   end
    #
    # @return [Module]
    #
    # @api public
    def self.call(options = {}, &block)
      config  = Configuration.build(&block)
      options.each { |key, value| config.public_send("#{key}=", value) }
      builder = new(config)
      builder.add_included_hook
      builder.add_extended_hook
      builder.module
    end

    # @api private
    def self.pending
      @pending ||= []
    end

    # Initializes a new ModuleBuilder
    #
    # @param [Configuration] configuration
    #
    # @param [Module] mod
    #
    # @return [undefined]
    #
    # @api private
    def initialize(configuration, mod = Module.new)
      @configuration = configuration
      @module        = mod
    end

    # Adds the .included hook to the anonymous module which then defines the
    # .attribute method to override the default.
    #
    # @return [Module]
    #
    # @api private
    def add_included_hook
      with_attribute_method do |attribute_method|
        constructor     = configuration.constructor
        mass_assignment = configuration.mass_assignment
        finalize        = configuration.finalize
        extensions      = core_extensions
        inclusions      = core_inclusions

        self.module.define_singleton_method :included do |object|
          super(object)
          Builder.pending << object unless finalize
          extensions.each { |mod| object.extend(mod) }
          inclusions.each { |mod| object.send(:include, mod) }
          object.send(:include, Model::Constructor)    if constructor
          object.send(:include, Model::MassAssignment) if mass_assignment
          object.send(:define_singleton_method, :attribute, attribute_method)
        end
      end
    end

    # @api private
    def add_extended_hook
      with_attribute_method do |attribute_method|
        mass_assignment = configuration.mass_assignment
        extensions      = core_inclusions + core_extensions

        self.module.define_singleton_method :extended do |object|
          super(object)
          extensions.each { |mod| object.extend(mod) }
          object.extend(Model::MassAssignment) if mass_assignment
          object.send :define_singleton_method, :attribute, attribute_method
        end
      end
    end

    # @api private
    def module_options
      { :coerce             => configuration.coerce,
        :finalize           => configuration.finalize,
        :strict             => configuration.strict,
        :configured_coercer => configuration.coercer }
    end

    # @api private
    def core_inclusions
      [Model::Core]
    end

    # @api private
    def core_extensions
      []
    end

    private

    # Wrapper for the attribute method that is used in .add_included_hook
    # The coercer is passed in the unused key :configured_coercer to allow the
    # property encapsulation by Virtus::Attribute::Coercer, where the
    # coercion method is known.
    #
    # @return [Proc(lambda)]
    #
    # @api private
    def attribute_method
      module_options = self.module_options

      lambda do |name, type = Object, options = {}|
        super(name, type, module_options.merge(options))
      end
    end

    # @api private
    def with_attribute_method
      yield(attribute_method)
    end

  end # class Builder

  # @private
  class ModelBuilder < Builder
  end # ModelBuilder

  # @private
  class ModuleBuilder < Builder

    # @api private
    def add_included_hook
      with_attribute_method do |attribute_method|
        inclusions     = core_inclusions

        inclusions << Model::Constructor    if configuration.constructor
        inclusions << Model::MassAssignment if configuration.mass_assignment

        self.module.define_singleton_method :included do |object|
          super(object)
          object.extend(ModuleExtensions)
          object.instance_variable_set('@inclusions', inclusions)
          object.send(:define_singleton_method, :attribute, attribute_method)
        end
      end
    end

  end # ModuleBuilder

  # @private
  class ValueObjectBuilder < Builder

    # @api private
    def initialize(configuration, mod = Module.new)
      super
      @configuration.constructor = true
    end

    # @api private
    def module_options
      super.update(:writer => :private)
    end

    # @api private
    def core_inclusions
      super << ValueObject::AllowedWriterMethods << ValueObject::InstanceMethods
    end

    # @api private
    def core_extensions
      super << ValueObject::AllowedWriterMethods
    end

  end # ValueObjectBuilder

end # module Virtus
