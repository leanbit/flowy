module Flowy
  module Concern
    # Internal runtime that wraps a step with hooks, dispatches keyword args
    # from result.data, and converts raised errors into Failures according to
    # the rescue: / on_error: / rescue_errors: contract.
    module StepRunner
      private

      # Execution order around each step:
      #   global before  →  class before  →  per-step before
      #     global around [ class around [ per-step around [ step ] ] ]
      #   per-step after  →  class after  →  global after
      def call_step_with_hooks(step_def, previous_result, rescue_errors:)
        is_tap    = step_def[:tap]
        step_name = step_def[:name]

        (Flowy::Concern._flowy_global_before_hooks + self.class._flowy_before_hooks).each do |hook|
          hook.call(step_name, previous_result)
        end
        if (ps_before = step_def[:before_step])
          resolve_hook(ps_before).call(step_name, previous_result)
        end

        innermost = lambda do
          raw = call_step(step_def, previous_result, rescue_errors: rescue_errors)
          is_tap ? previous_result : raw
        end

        all_around = Flowy::Concern._flowy_global_around_hooks + self.class._flowy_around_hooks
        all_around += [resolve_hook(step_def[:around_step])] if step_def[:around_step]

        chain = all_around.reverse.reduce(innermost) do |inner, hook|
          lambda { hook.call(step_name, previous_result) { inner.call } }
        end

        result = chain.call

        unless result.is_a?(Flowy::Result)
          raise TypeError,
            "around_step hook for '#{step_name}' must return a Flowy::Success or Flowy::Failure, got #{result.class}"
        end

        if (ps_after = step_def[:after_step])
          resolve_hook(ps_after).call(step_name, result)
        end
        (self.class._flowy_after_hooks + Flowy::Concern._flowy_global_after_hooks).each do |hook|
          hook.call(step_name, result)
        end

        result
      end

      def resolve_hook(hook)
        hook.is_a?(Symbol) ? method(hook) : hook
      end

      # `:previous_result` is a reserved keyword: when declared by a step, it
      # always receives the Flowy::Result object, regardless of any value with
      # the same key in previous_result.data.
      def build_step_kwargs(name, previous_result)
        m      = method(name)
        params = m.parameters   # [[:keyreq, :age], [:key, :name], [:keyrest, :opts], ...]

        kwargs       = {}
        has_keyrest  = params.any? { |type, _| type == :keyrest }
        explicit_keys = params
                          .select { |type, _| type == :keyreq || type == :key }
                          .map    { |type, pname| [pname, type == :keyreq] }

        explicit_keys.each do |pname, required|
          if pname == :previous_result
            kwargs[:previous_result] = previous_result
          elsif required
            unless previous_result.data.key?(pname)
              raise ArgumentError,
                "Step '#{name}' requires key #{pname.inspect} but it is missing from result.data " \
                "(available: #{previous_result.data.keys.inspect})"
            end
            kwargs[pname] = previous_result.data[pname]
          else
            # optional keyword (has a default): pass it only if present in data,
            # otherwise let Ruby apply the declared default.
            kwargs[pname] = previous_result.data[pname] if previous_result.data.key?(pname)
          end
        end

        if has_keyrest
          declared_names = explicit_keys.map(&:first).reject { |p| p == :previous_result }
          data_keys_to_pass = previous_result.data.keys - declared_names
          data_keys_to_pass.each { |k| kwargs[k] = previous_result.data[k] }
        end

        kwargs
      end

      def call_step(step_def, previous_result, rescue_errors:)
        name     = step_def[:name]
        is_tap   = step_def[:tap]
        rescues  = step_def[:rescue]
        on_error = step_def[:on_error]

        result =
          if name.is_a?(Symbol)
            public_send(name, **build_step_kwargs(name, previous_result))
          elsif name.is_a?(Flowy::Pipeline)
            name.call(starting_data: previous_result.data, rescue_errors: rescue_errors, context: self)
          elsif name.respond_to?(:call)
            name.call(previous_result: previous_result)
          else
            raise ArgumentError, "Step must be a Symbol, Flowy::Pipeline or callable, got #{name.class}"
          end

        return previous_result if is_tap

        unless result.is_a?(Flowy::Success) || result.is_a?(Flowy::Failure)
          raise TypeError, "Step '#{name}' must return a Flowy::Success or Flowy::Failure, got #{result.class}"
        end

        result
      rescue StandardError => e
        in_rescues = rescues.any? { |klass| e.is_a?(klass) }
        raise unless in_rescues || rescue_errors

        if in_rescues && on_error
          public_send(on_error, e, previous_result: previous_result)
        else
          failure(
            error_code: :step_raised_error,
            error_data: { step: name.is_a?(Symbol) ? name : name.class.name, message: e.message }
          )
        end
      end
    end
  end
end
