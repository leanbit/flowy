require_relative 'concern/step_runner'

module Flowy
  module Concern
    @_flowy_global_around_hooks = []
    @_flowy_global_before_hooks = []
    @_flowy_global_after_hooks  = []

    class << self
      attr_reader :_flowy_global_around_hooks,
                  :_flowy_global_before_hooks,
                  :_flowy_global_after_hooks

      def included(base)
        base.extend(ClassMethods)
      end

      # Block signature: |step_name, previous_result, &call|
      def around_step(&block)
        @_flowy_global_around_hooks << block
      end

      # Block signature: |step_name, previous_result|
      def before_step(&block)
        @_flowy_global_before_hooks << block
      end

      # Block signature: |step_name, result|
      def after_step(&block)
        @_flowy_global_after_hooks << block
      end

      def clear_global_hooks!
        @_flowy_global_around_hooks = []
        @_flowy_global_before_hooks = []
        @_flowy_global_after_hooks  = []
      end
    end

    DEFAULT_STEP_DEF = {
      tap:         false,
      rescue:      [].freeze,
      on_error:    nil,
      before_step: nil,
      after_step:  nil,
      around_step: nil
    }.freeze
    private_constant :DEFAULT_STEP_DEF

    def self._build_step_def(name, **overrides)
      DEFAULT_STEP_DEF.merge(name: name, **overrides)
    end

    module ClassMethods

      def success(**kwargs)
        Flowy::Result.success(**kwargs)
      end

      def failure(**kwargs)
        Flowy::Result.failure(**kwargs)
      end

      # `rescue:` is captured via **opts because `rescue` is a Ruby reserved
      # word and cannot be referenced as a bare local variable inside a method.
      def step(name, on_error: nil, before_step: nil, after_step: nil, around_step: nil, **opts)
        unknown = opts.keys - [:rescue]
        raise ArgumentError, "unknown keyword: #{unknown.first}" if unknown.any?

        _flowy_steps << Flowy::Concern._build_step_def(
          name,
          rescue:      Array(opts[:rescue]),
          on_error:    on_error,
          before_step: before_step,
          after_step:  after_step,
          around_step: around_step
        )
      end

      def tap_step(name, before_step: nil, after_step: nil, around_step: nil)
        _flowy_steps << Flowy::Concern._build_step_def(
          name,
          tap:         true,
          before_step: before_step,
          after_step:  after_step,
          around_step: around_step
        )
      end

      def _flowy_steps
        @_flowy_steps ||= []
      end

      # Block signature: |step_name, previous_result, &call|
      def around_step(&block)
        _flowy_around_hooks << block
      end

      # Block signature: |step_name, previous_result|
      def before_step(&block)
        _flowy_before_hooks << block
      end

      # Block signature: |step_name, result|
      def after_step(&block)
        _flowy_after_hooks << block
      end

      def _flowy_around_hooks
        @_flowy_around_hooks ||= []
      end

      def _flowy_before_hooks
        @_flowy_before_hooks ||= []
      end

      def _flowy_after_hooks
        @_flowy_after_hooks ||= []
      end
    end

    include StepRunner

    def success(**kwargs)
      self.class.success(**kwargs)
    end

    def failure(**kwargs)
      self.class.failure(**kwargs)
    end

    def run_steps(starting_data: {}, steps: nil, rescue_errors: false)
      initial    = success(data: starting_data)
      step_list  = steps ? steps.map { |s| Flowy::Concern._build_step_def(s) }
                         : self.class._flowy_steps

      step_list.reduce(initial) do |current_result, step_def|
        break current_result if current_result.failure?

        call_step_with_hooks(step_def, current_result, rescue_errors: rescue_errors)
      end
    end
  end
end
