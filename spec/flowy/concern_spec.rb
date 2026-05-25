require 'spec_helper'

RSpec.describe Flowy::Concern do
  let(:service_class) do
    Class.new do
      include Flowy::Concern
    end
  end

  let(:service_instance) { service_class.new }

  # --- Class methods ----------------------------------------------------------

  describe '.success (class method)' do
    it 'returns a Flowy::Success' do
      expect(service_class.success).to be_a(Flowy::Success)
    end

    it 'accepts data' do
      result = service_class.success(data: { id: 1 })
      expect(result.data).to eq({ id: 1 })
    end

    it 'accepts warnings' do
      result = service_class.success(warnings: ['warning'])
      expect(result.warnings).to eq(['warning'])
    end

    it 'defaults data and warnings' do
      result = service_class.success
      expect(result.data).to eq({})
      expect(result.warnings).to eq([])
    end
  end

  describe '.failure (class method)' do
    it 'returns a Flowy::Failure' do
      expect(service_class.failure(error_code: :err)).to be_a(Flowy::Failure)
    end

    it 'sets error_code' do
      result = service_class.failure(error_code: :not_found)
      expect(result.error_code).to eq(:not_found)
    end

    it 'accepts error_data' do
      result = service_class.failure(error_code: :err, error_data: { field: 'name' })
      expect(result.error_data).to eq({ field: 'name' })
    end

    it 'accepts error_title' do
      result = service_class.failure(error_code: :err, error_title: 'Title')
      expect(result.error_title).to eq('Title')
    end

    it 'accepts error_description' do
      result = service_class.failure(error_code: :err, error_description: 'Description')
      expect(result.error_description).to eq('Description')
    end
  end

  # --- Instance methods --------------------------------------------------------

  describe '#success (instance method)' do
    it 'returns a Flowy::Success' do
      expect(service_instance.success).to be_a(Flowy::Success)
    end

    it 'accepts data' do
      result = service_instance.success(data: { name: 'Bob' })
      expect(result.data).to eq({ name: 'Bob' })
    end

    it 'accepts warnings' do
      result = service_instance.success(warnings: ['w'])
      expect(result.warnings).to eq(['w'])
    end

    it 'defaults data and warnings' do
      result = service_instance.success
      expect(result.data).to eq({})
      expect(result.warnings).to eq([])
    end
  end

  describe '#failure (instance method)' do
    it 'returns a Flowy::Failure' do
      expect(service_instance.failure(error_code: :err)).to be_a(Flowy::Failure)
    end

    it 'sets error_code' do
      result = service_instance.failure(error_code: :unauthorized)
      expect(result.error_code).to eq(:unauthorized)
    end

    it 'accepts error_data' do
      result = service_instance.failure(error_code: :err, error_data: { x: 1 })
      expect(result.error_data).to eq({ x: 1 })
    end

    it 'accepts error_title' do
      result = service_instance.failure(error_code: :err, error_title: 'T')
      expect(result.error_title).to eq('T')
    end

    it 'accepts error_description' do
      result = service_instance.failure(error_code: :err, error_description: 'D')
      expect(result.error_description).to eq('D')
    end
  end

  # --- Instance -> class delegation ---------------------------------------------

  describe 'delegation from instance to class' do
    it '#success delegates to .success' do
      expect(service_class).to receive(:success).with(data: { k: 'v' }).and_call_original
      service_instance.success(data: { k: 'v' })
    end

    it '#failure delegates to .failure' do
      expect(service_class).to receive(:failure).with(error_code: :err).and_call_original
      service_instance.failure(error_code: :err)
    end
  end

  # --- run_steps ---------------------------------------------------------------

  describe '#run_steps' do
    let(:service_class) do
      Class.new do
        include Flowy::Concern

        def double(previous_result:)
          success(data: previous_result.data.merge(doubled: previous_result.data[:n] * 2))
        end

        def add_one(previous_result:)
          success(data: previous_result.data.merge(n: previous_result.data[:n] + 1))
        end

        def always_fail(previous_result:)
          failure(error_code: :forced_failure)
        end

        def bad_return(previous_result:)
          'not a result'
        end

        def raises(previous_result:)
          raise RuntimeError, 'boom'
        end
      end
    end

    let(:instance) { service_class.new }

    it 'returns a Success when all steps succeed' do
      result = instance.run_steps(starting_data: { n: 3 }, steps: [:add_one, :double])
      expect(result).to be_a(Flowy::Success)
      expect(result.data).to eq({ n: 4, doubled: 8 })
    end

    it 'returns the initial Success when steps is empty' do
      result = instance.run_steps(starting_data: { x: 1 }, steps: [])
      expect(result).to be_a(Flowy::Success)
      expect(result.data).to eq({ x: 1 })
    end

    it 'defaults starting_data to an empty hash' do
      result = instance.run_steps(steps: [])
      expect(result.data).to eq({})
    end

    it 'short-circuits on the first Failure' do
      second_called = false
      service_class.define_method(:second) do |previous_result:|
        second_called = true
        success(data: previous_result.data)
      end

      result = instance.run_steps(starting_data: { n: 1 }, steps: [:always_fail, :second])
      expect(result).to be_a(Flowy::Failure)
      expect(result.error_code).to eq(:forced_failure)
      expect(second_called).to be false
    end

    it 'accepts callable (lambda) steps' do
      step = ->(previous_result:) { Flowy::Success.new(data: previous_result.data.merge(flag: true)) }
      result = instance.run_steps(starting_data: { n: 0 }, steps: [step])
      expect(result.data[:flag]).to be true
    end

    it 'raises TypeError when a step returns an invalid type' do
      expect {
        instance.run_steps(steps: [:bad_return])
      }.to raise_error(TypeError, /Flowy::Success or Flowy::Failure/)
    end

    it 'raises ArgumentError for invalid step type' do
      expect {
        instance.run_steps(steps: [42])
      }.to raise_error(ArgumentError, /Symbol.*callable/)
    end

    context 'with rescue_errors: true' do
      it 'converts a raised StandardError into a Failure' do
        result = instance.run_steps(steps: [:raises], rescue_errors: true)
        expect(result).to be_a(Flowy::Failure)
        expect(result.error_code).to eq(:step_raised_error)
        expect(result.error_data[:message]).to eq('boom')
      end

      it 'includes the step name in error_data' do
        result = instance.run_steps(steps: [:raises], rescue_errors: true)
        expect(result.error_data[:step]).to eq(:raises)
      end

      it 'converts a raised ArgumentError into a Failure' do
        svc = Class.new do
          include Flowy::Concern
          step :boom
          def boom(previous_result:) = raise ArgumentError, 'bad'
        end

        result = svc.new.run_steps(rescue_errors: true)
        expect(result).to be_a(Flowy::Failure)
        expect(result.error_code).to eq(:step_raised_error)
        expect(result.error_data[:message]).to eq('bad')
      end

      it 'converts a raised TypeError into a Failure' do
        svc = Class.new do
          include Flowy::Concern
          step :boom
          def boom(previous_result:) = raise TypeError, 'oops'
        end

        result = svc.new.run_steps(rescue_errors: true)
        expect(result).to be_a(Flowy::Failure)
        expect(result.error_code).to eq(:step_raised_error)
        expect(result.error_data[:message]).to eq('oops')
      end
    end

    context 'with rescue_errors: false (default)' do
      it 'lets StandardErrors propagate' do
        expect {
          instance.run_steps(steps: [:raises])
        }.to raise_error(RuntimeError, 'boom')
      end

      it 'lets ArgumentError propagate when not declared in rescue:' do
        svc = Class.new do
          include Flowy::Concern
          step :boom
          def boom(previous_result:) = raise ArgumentError, 'bad'
        end

        expect { svc.new.run_steps }.to raise_error(ArgumentError, 'bad')
      end

      it 'lets TypeError propagate when not declared in rescue:' do
        svc = Class.new do
          include Flowy::Concern
          step :boom
          def boom(previous_result:) = raise TypeError, 'oops'
        end

        expect { svc.new.run_steps }.to raise_error(TypeError, 'oops')
      end
    end
  end

  # --- .step DSL ---------------------------------------------------------------

  describe '.step DSL' do
    let(:service_class) do
      Class.new do
        include Flowy::Concern

        step :add_one
        step :double

        def add_one(previous_result:)
          success(data: previous_result.data.merge(n: previous_result.data[:n] + 1))
        end

        def double(previous_result:)
          success(data: previous_result.data.merge(n: previous_result.data[:n] * 2))
        end
      end
    end

    let(:instance) { service_class.new }

    it 'registers steps on the class' do
      expect(service_class._flowy_steps.map { |s| s[:name] }).to eq([:add_one, :double])
    end

    it 'raises ArgumentError when step is called with an unknown keyword' do
      expect {
        Class.new do
          include Flowy::Concern
          step :foo, bogus: 1
        end
      }.to raise_error(ArgumentError, /unknown keyword: bogus/)
    end

    it 'run_steps uses class-level steps when steps: is omitted' do
      result = instance.run_steps(starting_data: { n: 3 })
      expect(result.data[:n]).to eq(8) # (3+1)*2
    end

    it 'run_steps with explicit steps: overrides the DSL pipeline' do
      result = instance.run_steps(starting_data: { n: 3 }, steps: [:add_one])
      expect(result.data[:n]).to eq(4)
    end

    it 'subclass inherits parent steps and can add its own' do
      parent = Class.new do
        include Flowy::Concern
        step :first
        def first(previous_result:) = success(data: previous_result.data.merge(first: true))
      end
      child = Class.new(parent) do
        step :second
        def second(previous_result:) = success(data: previous_result.data.merge(second: true))
      end
      # child has its own _flowy_steps (not shared with parent)
      expect(child._flowy_steps.map { |s| s[:name] }).to eq([:second])
    end
  end

  # --- .rescue_step ------------------------------------------------------------

  describe '.rescue_step (via step rescue: on_error:)' do
    let(:service_class) do
      Class.new do
        include Flowy::Concern

        step :risky, rescue: [ArgumentError], on_error: :handle_arg_error
        step :safe

        def risky(previous_result:)
          raise ArgumentError, 'bad arg'
        end

        def handle_arg_error(error, previous_result:)
          failure(error_code: :handled_arg_error, error_data: { message: error.message })
        end

        def safe(previous_result:)
          success(data: previous_result.data.merge(safe: true))
        end
      end
    end

    let(:instance) { service_class.new }

    it 'calls the on_error handler when the declared exception is raised' do
      result = instance.run_steps
      expect(result).to be_a(Flowy::Failure)
      expect(result.error_code).to eq(:handled_arg_error)
      expect(result.error_data[:message]).to eq('bad arg')
    end

    it 'short-circuits: the step after the failing one is not called' do
      safe_called = false
      service_class.define_method(:safe) do |previous_result:|
        safe_called = true
        success(data: {})
      end
      instance.run_steps
      expect(safe_called).to be false
    end

    it 'lets undeclared exception classes propagate' do
      service_class.define_method(:risky) do |previous_result:|
        raise RuntimeError, 'unhandled'
      end
      expect { instance.run_steps }.to raise_error(RuntimeError, 'unhandled')
    end

    context 'without on_error (generic rescue to :step_raised_error)' do
      let(:service_class) do
        Class.new do
          include Flowy::Concern
          step :risky, rescue: [TypeError]
          def risky(previous_result:) = raise(TypeError, 'type mismatch')
        end
      end

      it 'converts the exception to a Failure with :step_raised_error' do
        result = service_class.new.run_steps
        expect(result.error_code).to eq(:step_raised_error)
        expect(result.error_data[:message]).to eq('type mismatch')
      end
    end
  end

  # --- .tap_step ---------------------------------------------------------------

  describe '.tap_step DSL' do
    let(:log) { [] }

    let(:service_class) do
      outer_log = log
      Class.new do
        include Flowy::Concern

        step     :compute
        tap_step :audit
        step     :finalize

        define_method(:compute) do |previous_result:|
          success(data: previous_result.data.merge(computed: true))
        end

        define_method(:audit) do |previous_result:|
          outer_log << :audited
          # return value is intentionally wrong to prove it is ignored
          'side-effect only'
        end

        define_method(:finalize) do |previous_result:|
          success(data: previous_result.data.merge(finalized: true))
        end
      end
    end

    let(:instance) { service_class.new }

    it 'executes the tap_step method as a side-effect' do
      instance.run_steps
      expect(log).to eq([:audited])
    end

    it 'forwards the previous result unchanged regardless of the tap return value' do
      result = instance.run_steps(starting_data: { n: 1 })
      expect(result).to be_a(Flowy::Success)
      expect(result.data).to include(computed: true, finalized: true)
    end

    it 'does not short-circuit even if the tap method returns a Failure' do
      service_class.define_method(:audit) do |previous_result:|
        failure(error_code: :should_be_ignored)
      end
      result = instance.run_steps
      expect(result).to be_a(Flowy::Success)
    end
  end

  # --- Per-step hooks (before_step:, after_step:, around_step: on step DSL) ---

  describe 'per-step hooks via step DSL options' do
    after { Flowy::Concern.clear_global_hooks! }

    let(:log) { [] }

    context 'before_step: as Symbol' do
      let(:service_class) do
        outer_log = log
        Class.new do
          include Flowy::Concern

          step :compute, before_step: :log_before
          step :finalize

          define_method(:compute)    { |previous_result:| success(data: previous_result.data.merge(computed: true)) }
          define_method(:finalize)   { |previous_result:| success(data: previous_result.data.merge(finalized: true)) }
          define_method(:log_before) { |_name, _prev| outer_log << :before_compute }
        end
      end

      it 'calls the before hook only for the declared step' do
        service_class.new.run_steps
        expect(log).to eq([:before_compute])
      end
    end

    context 'after_step: as Symbol' do
      let(:service_class) do
        outer_log = log
        Class.new do
          include Flowy::Concern

          step :compute
          step :finalize, after_step: :log_after

          define_method(:compute)   { |previous_result:| success(data: { computed: true }) }
          define_method(:finalize)  { |previous_result:| success(data: previous_result.data.merge(finalized: true)) }
          define_method(:log_after) { |_name, res| outer_log << res.data.keys }
        end
      end

      it 'calls the after hook only for the declared step, with the step result' do
        service_class.new.run_steps
        expect(log).to eq([[:computed, :finalized]])
      end
    end

    context 'around_step: as Symbol' do
      let(:service_class) do
        outer_log = log
        Class.new do
          include Flowy::Concern

          step :compute, around_step: :trace
          step :finalize

          define_method(:compute)  { |previous_result:| success(data: { computed: true }) }
          define_method(:finalize) { |previous_result:| success(data: previous_result.data.merge(finalized: true)) }
          define_method(:trace) do |_name, _prev, &call|
            outer_log << :trace_in
            r = call.()
            outer_log << :trace_out
            r
          end
        end
      end

      it 'wraps only the declared step' do
        service_class.new.run_steps
        expect(log).to eq([:trace_in, :trace_out])
      end
    end

    context 'before_step: as callable (lambda)' do
      it 'accepts a lambda as before_step' do
        outer_log = log
        probe     = ->(name, _prev) { outer_log << name }

        svc = Class.new do
          include Flowy::Concern
          step :work, before_step: probe
          define_method(:work) { |previous_result:| success }
        end

        svc.new.run_steps
        expect(log).to eq([:work])
      end
    end

    context 'after_step: as callable (lambda)' do
      it 'accepts a lambda as after_step' do
        outer_log = log
        probe     = ->(_name, res) { outer_log << res.class }

        svc = Class.new do
          include Flowy::Concern
          step :work, after_step: probe
          define_method(:work) { |previous_result:| success }
        end

        svc.new.run_steps
        expect(log).to eq([Flowy::Success])
      end
    end

    context 'around_step: as callable (lambda)' do
      it 'accepts a lambda as around_step and can short-circuit' do
        outer_log = log
        blocker   = ->(_name, _prev, &_call) { Flowy::Result.failure(error_code: :blocked) }

        svc = Class.new do
          include Flowy::Concern
          step :work, around_step: blocker
          define_method(:work) { |previous_result:| outer_log << :should_not_run; success }
        end

        result = svc.new.run_steps
        expect(result.error_code).to eq(:blocked)
        expect(log).to be_empty
      end
    end

    context 'interaction with class-level and global hooks' do
      it 'per-step hooks run after class-level hooks in the correct order' do
        outer_log = log
        Flowy::Concern.before_step { |_, _| outer_log << :global_before }
        Flowy::Concern.after_step  { |_, _| outer_log << :global_after  }

        svc = Class.new do
          include Flowy::Concern
          before_step { |_, _| outer_log << :class_before }
          after_step  { |_, _| outer_log << :class_after  }

          step :work,
            before_step:  ->(_n, _p) { outer_log << :step_before },
            around_step:  ->(_n, _p, &c) { outer_log << :around_in; r = c.(); outer_log << :around_out; r },
            after_step:   ->(_n, _r) { outer_log << :step_after }

          define_method(:work) { |previous_result:| outer_log << :step; success }
        end

        svc.new.run_steps
        expect(log).to eq([
          :global_before, :class_before, :step_before,
          :around_in, :step, :around_out,
          :step_after, :class_after, :global_after
        ])
      end
    end

    context 'with tap_step' do
      it 'tap_step also accepts before_step: and after_step:' do
        outer_log = log

        svc = Class.new do
          include Flowy::Concern
          tap_step :side_effect,
            before_step: ->(_n, _p) { outer_log << :before },
            after_step:  ->(_n, _r) { outer_log << :after  }

          step :finalize
          define_method(:side_effect) { |previous_result:| 'ignored' }
          define_method(:finalize)    { |previous_result:| success }
        end

        svc.new.run_steps
        expect(log).to eq([:before, :after])
      end
    end
  end



  describe '.before_step / .after_step (class-level hooks)' do
    after { Flowy::Concern.clear_global_hooks! }

    let(:log) { [] }

    let(:service_class) do
      outer_log = log
      Class.new do
        include Flowy::Concern

        before_step { |name, _prev| outer_log << :"before_#{name}" }
        after_step  { |name, _res|  outer_log << :"after_#{name}"  }

        step :compute
        step :finalize

        define_method(:compute)  { |previous_result:| success(data: previous_result.data.merge(computed: true)) }
        define_method(:finalize) { |previous_result:| success(data: previous_result.data.merge(finalized: true)) }
      end
    end

    let(:instance) { service_class.new }

    it 'calls before_step before the step and after_step after the step' do
      instance.run_steps
      expect(log).to eq([:before_compute, :after_compute, :before_finalize, :after_finalize])
    end

    it 'before_step receives step_name and previous_result' do
      received = []
      service_class.before_step { |name, prev| received << [name, prev] }
      instance.run_steps(starting_data: { x: 1 })
      expect(received.first).to match([:compute, be_a(Flowy::Result)])
      expect(received.first[1].data).to include(x: 1)
    end

    it 'after_step receives step_name and the step result' do
      received = []
      service_class.after_step { |name, res| received << [name, res] }
      instance.run_steps
      expect(received.first).to match([:compute, be_a(Flowy::Result)])
      expect(received.last[1].data).to include(finalized: true)
    end

    it 'before_step is called even when a previous step failed (before short-circuit check)' do
      # short-circuit happens BEFORE call_step_with_hooks, so before_step
      # on the second step should NOT be called
      before_calls = []
      service_class.before_step { |name, _| before_calls << name }
      service_class.define_method(:compute) { |previous_result:| failure(error_code: :boom) }
      instance.run_steps
      expect(before_calls).to eq([:compute])
    end

    it 'after_step receives the Failure when the step fails' do
      after_results = []
      service_class.after_step { |_name, res| after_results << res }
      service_class.define_method(:compute) { |previous_result:| failure(error_code: :boom) }
      instance.run_steps
      expect(after_results.first).to be_a(Flowy::Failure)
      expect(after_results.first.error_code).to eq(:boom)
    end

    it 'after_step is called with previous_result for tap_steps' do
      svc = Class.new do
        include Flowy::Concern
        step     :compute
        tap_step :side_effect
        define_method(:compute)     { |previous_result:| success(data: { n: 1 }) }
        define_method(:side_effect) { |previous_result:| 'ignored' }
      end
      after_results = []
      svc.after_step { |_name, res| after_results << res }
      svc.new.run_steps
      # after_step for the tap should receive the forwarded previous_result
      tap_result = after_results.find { |r| r.data == { n: 1 } }
      expect(tap_result).to be_a(Flowy::Success)
    end

    it 'does not affect other classes' do
      other = Class.new { include Flowy::Concern }
      expect(other._flowy_before_hooks).to be_empty
      expect(other._flowy_after_hooks).to be_empty
    end
  end

  # --- Flowy::Concern.before_step / .after_step (global) -----------------------

  describe 'Flowy::Concern.before_step / .after_step (global hooks)' do
    after { Flowy::Concern.clear_global_hooks! }

    let(:log) { [] }

    it 'global before_step runs for any service class' do
      outer_log = log
      Flowy::Concern.before_step { |name, _| outer_log << name }

      svc = Class.new do
        include Flowy::Concern
        step :work
        define_method(:work) { |previous_result:| success }
      end

      svc.new.run_steps
      expect(log).to include(:work)
    end

    it 'global after_step runs for any service class' do
      outer_log = log
      Flowy::Concern.after_step { |name, _| outer_log << name }

      svc = Class.new do
        include Flowy::Concern
        step :work
        define_method(:work) { |previous_result:| success }
      end

      svc.new.run_steps
      expect(log).to include(:work)
    end

    it 'global before runs before class before, global after runs after class after' do
      Flowy::Concern.before_step { |_n, _p| log << :global_before }
      Flowy::Concern.after_step  { |_n, _r| log << :global_after  }

      outer_log = log
      svc = Class.new do
        include Flowy::Concern
        before_step { |_n, _p| outer_log << :class_before }
        after_step  { |_n, _r| outer_log << :class_after  }
        step :work
        define_method(:work) { |previous_result:| outer_log << :step; success }
      end

      svc.new.run_steps
      expect(log).to eq([:global_before, :class_before, :step, :class_after, :global_after])
    end

    it 'clear_global_hooks! removes global before and after hooks too' do
      Flowy::Concern.before_step { |_, _| log << :before }
      Flowy::Concern.after_step  { |_, _| log << :after  }
      Flowy::Concern.clear_global_hooks!

      svc = Class.new do
        include Flowy::Concern
        step :work
        define_method(:work) { |previous_result:| success }
      end

      svc.new.run_steps
      expect(log).to be_empty
    end
  end

  # --- Full execution order (before + around + after) --------------------------

  describe 'full execution order: before + around + after' do
    after { Flowy::Concern.clear_global_hooks! }

    it 'executes hooks in the correct nested order' do
      log = []

      Flowy::Concern.before_step { |_, _| log << :global_before }
      Flowy::Concern.after_step  { |_, _| log << :global_after  }

      svc = Class.new do
        include Flowy::Concern

        before_step { |_, _| log << :class_before }
        around_step { |_, _, &call| log << :around_in; r = call.(); log << :around_out; r }
        after_step  { |_, _| log << :class_after  }

        step :work
        define_method(:work) { |previous_result:| log << :step; success }
      end

      svc.new.run_steps
      expect(log).to eq([:global_before, :class_before, :around_in, :step, :around_out, :class_after, :global_after])
    end
  end



  describe '.around_step (class-level hook)' do
    after { Flowy::Concern.clear_global_hooks! }

    let(:log) { [] }

    let(:service_class) do
      outer_log = log
      Class.new do
        include Flowy::Concern

        around_step do |step_name, _prev, &call|
          outer_log << :"before_#{step_name}"
          result = call.()
          outer_log << :"after_#{step_name}"
          result
        end

        step :compute
        step :finalize

        define_method(:compute) do |previous_result:|
          success(data: previous_result.data.merge(computed: true))
        end

        define_method(:finalize) do |previous_result:|
          success(data: previous_result.data.merge(finalized: true))
        end
      end
    end

    let(:instance) { service_class.new }

    it 'wraps each step with the hook (before and after callbacks)' do
      instance.run_steps
      expect(log).to eq([:before_compute, :after_compute, :before_finalize, :after_finalize])
    end

    it 'receives the correct step name in the hook' do
      names = []
      service_class.around_step { |name, _prev, &call| names << name; call.() }
      instance.run_steps
      expect(names).to include(:compute, :finalize)
    end

    it 'receives previous_result in the hook' do
      received = []
      service_class.around_step do |_name, prev, &call|
        received << prev
        call.()
      end
      instance.run_steps(starting_data: { x: 1 })
      expect(received.first).to be_a(Flowy::Result)
      expect(received.first.data).to include(x: 1)
    end

    it 'forwards the result from call.() through the hook' do
      result = instance.run_steps
      expect(result).to be_a(Flowy::Success)
      expect(result.data).to include(computed: true, finalized: true)
    end

    it 'allows the hook to short-circuit by returning a Failure without calling call.()' do
      service_class.around_step do |step_name, _prev, &_call|
        Flowy::Result.failure(error_code: :hook_blocked, error_data: { step: step_name })
      end
      result = instance.run_steps
      expect(result).to be_a(Flowy::Failure)
      expect(result.error_code).to eq(:hook_blocked)
    end

    it 'raises TypeError if the hook returns a non-Result value' do
      service_class.around_step { |_n, _p, &_c| 'not a result' }
      expect { instance.run_steps }.to raise_error(TypeError, /around_step hook/)
    end

    it 'does not affect other classes (hooks are class-level)' do
      other_class = Class.new { include Flowy::Concern }
      expect(other_class._flowy_around_hooks).to be_empty
    end

    context 'with tap_step' do
      let(:service_class) do
        outer_log = log
        Class.new do
          include Flowy::Concern

          around_step do |step_name, _prev, &call|
            outer_log << :"hook_#{step_name}"
            call.()
          end

          step     :compute
          tap_step :side_effect
          step     :finalize

          define_method(:compute) do |previous_result:|
            success(data: previous_result.data.merge(computed: true))
          end

          define_method(:side_effect) do |previous_result:|
            outer_log << :side_effect_ran
            'ignored return value'
          end

          define_method(:finalize) do |previous_result:|
            success(data: previous_result.data.merge(finalized: true))
          end
        end
      end

      it 'runs the hook around tap_steps too' do
        instance.run_steps
        expect(log).to include(:hook_side_effect)
      end

      it 'still forwards previous_result unchanged after a tap_step hook' do
        result = instance.run_steps(starting_data: { n: 1 })
        expect(result.data).to include(computed: true, finalized: true)
      end
    end
  end

  # --- Flowy::Concern.around_step (global hook) --------------------------------

  describe 'Flowy::Concern.around_step (global hook)' do
    after { Flowy::Concern.clear_global_hooks! }

    let(:log) { [] }

    it 'wraps steps on any service class' do
      outer_log = log
      Flowy::Concern.around_step { |name, _prev, &call| outer_log << name; call.() }

      svc = Class.new do
        include Flowy::Concern
        step :run_it
        define_method(:run_it) { |previous_result:| success }
      end

      svc.new.run_steps
      expect(log).to include(:run_it)
    end

    it 'runs global hooks before class-level hooks' do
      Flowy::Concern.around_step { |_n, _p, &call| log << :global; call.() }

      svc = Class.new do
        include Flowy::Concern
        step :work
        define_method(:work) { |previous_result:| success }
      end
      svc.around_step { |_n, _p, &call| log << :local; call.() }

      svc.new.run_steps
      expect(log).to eq([:global, :local])
    end

    it 'multiple global hooks run in registration order (outermost first)' do
      Flowy::Concern.around_step { |_n, _p, &call| log << :first; call.() }
      Flowy::Concern.around_step { |_n, _p, &call| log << :second; call.() }

      svc = Class.new do
        include Flowy::Concern
        step :work
        define_method(:work) { |previous_result:| success }
      end

      svc.new.run_steps
      expect(log).to eq([:first, :second])
    end

    it 'clear_global_hooks! removes all global hooks' do
      Flowy::Concern.around_step { |_n, _p, &call| log << :should_not_run; call.() }
      Flowy::Concern.clear_global_hooks!

      svc = Class.new do
        include Flowy::Concern
        step :work
        define_method(:work) { |previous_result:| success }
      end

      svc.new.run_steps
      expect(log).to be_empty
    end

  end

  # --- Multiple hooks chaining -------------------------------------------------

  describe 'hook chaining (multiple class-level hooks)' do
    after { Flowy::Concern.clear_global_hooks! }

    let(:log) { [] }

    it 'composes multiple class-level hooks in registration order' do
      outer_log = log
      svc = Class.new do
        include Flowy::Concern

        around_step { |_n, _p, &call| outer_log << :hook_a_in;  r = call.(); outer_log << :hook_a_out; r }
        around_step { |_n, _p, &call| outer_log << :hook_b_in;  r = call.(); outer_log << :hook_b_out; r }

        step :work
        define_method(:work) { |previous_result:| outer_log << :step; success }
      end

      svc.new.run_steps
      expect(log).to eq([:hook_a_in, :hook_b_in, :step, :hook_b_out, :hook_a_out])
    end
  end

  # --- Data-kwargs step style --------------------------------------------------

  describe 'step keyword-argument dispatch' do
    # The framework inspects each step method's declared parameters and passes:
    #   - previous_result: (full Flowy::Result) if the method declares it
    #   - any other keyword param resolved from previous_result.data by name
    #   - ** rest receives remaining data keys not declared explicitly

    it 'passes only declared data keys to a method with no previous_result:' do
      svc = Class.new do
        include Flowy::Concern
        step :add_one
        step :double

        def add_one(n:, **rest)
          success(data: rest.merge(n: n + 1))
        end

        def double(n:, **rest)
          success(data: rest.merge(n: n * 2))
        end
      end

      result = svc.new.run_steps(starting_data: { n: 3 })
      expect(result.data[:n]).to eq(8) # (3+1)*2
    end

    it 'passes previous_result: AND data keys when both are declared' do
      svc = Class.new do
        include Flowy::Concern
        step :work

        def work(user_id:, previous_result:)
          success(data: { id: user_id, warnings: previous_result.warnings })
        end
      end

      result = svc.new.run_steps(starting_data: { user_id: 42 })
      expect(result.data[:id]).to eq(42)
      expect(result.data[:warnings]).to eq([])
    end

    it 'previous_result: is reserved — the Result object always wins over data[:previous_result]' do
      svc = Class.new do
        include Flowy::Concern
        step :work

        def work(previous_result:)
          success(data: { received_class: previous_result.class })
        end
      end

      result = svc.new.run_steps(starting_data: { previous_result: 'spurious value' })
      expect(result.data[:received_class]).to eq(Flowy::Success)
    end

    it 'classic style (only previous_result:) still works unchanged' do
      svc = Class.new do
        include Flowy::Concern
        step :work

        def work(previous_result:)
          success(data: previous_result.data.merge(done: true))
        end
      end

      result = svc.new.run_steps(starting_data: { x: 1 })
      expect(result.data).to include(x: 1, done: true)
    end

    it 'classic and keyword styles can coexist in the same pipeline' do
      svc = Class.new do
        include Flowy::Concern
        step :classic
        step :data_kw

        def classic(previous_result:)
          success(data: previous_result.data.merge(classic: true))
        end

        def data_kw(classic:, **rest)
          success(data: rest.merge(classic: classic, data_kw: true))
        end
      end

      result = svc.new.run_steps(starting_data: { x: 1 })
      expect(result.data).to include(classic: true, data_kw: true)
    end

    it '** rest receives remaining data keys not declared explicitly' do
      svc = Class.new do
        include Flowy::Concern
        step :work

        def work(n:, **rest)
          success(data: rest.merge(n: n, keys_in_rest: rest.keys))
        end
      end

      result = svc.new.run_steps(starting_data: { n: 1, extra: 'hello', other: 99 })
      expect(result.data[:keys_in_rest]).to contain_exactly(:extra, :other)
    end

    it 'tap_step also supports keyword dispatch (return value is ignored)' do
      log = []
      svc = Class.new do
        include Flowy::Concern
        step     :build
        tap_step :audit
        step     :finalize

        define_method(:build)    { |n:, **r| success(data: r.merge(n: n, built: true)) }
        define_method(:audit)    { |n:, **_r| log << n }
        define_method(:finalize) { |previous_result:| success(data: previous_result.data.merge(finalized: true)) }
      end

      result = svc.new.run_steps(starting_data: { n: 5 })
      expect(log).to eq([5])
      expect(result.data).to include(built: true, finalized: true)
    end

    it 'raises ArgumentError with a clear message when a required data key is missing' do
      svc = Class.new do
        include Flowy::Concern
        step :strict
        def strict(required_key:)
          success
        end
      end

      expect {
        svc.new.run_steps(starting_data: { other: 1 })
      }.to raise_error(ArgumentError, /strict.*required_key.*missing from result\.data/i)
    end

    it 'does NOT raise when an optional keyword (with default) is absent from data' do
      svc = Class.new do
        include Flowy::Concern
        step :work
        def work(n:, label: 'default')
          success(data: { n: n, label: label })
        end
      end

      result = svc.new.run_steps(starting_data: { n: 5 })
      expect(result.data[:label]).to eq('default')
    end

    it 'overrides the default when the optional key IS present in data' do
      svc = Class.new do
        include Flowy::Concern
        step :work
        def work(n:, label: 'default')
          success(data: { n: n, label: label })
        end
      end

      result = svc.new.run_steps(starting_data: { n: 5, label: 'custom' })
      expect(result.data[:label]).to eq('custom')
    end

    context 'with rescue_errors: true' do
      it 'converts a raised StandardError into a Failure (keyword style)' do
        svc = Class.new do
          include Flowy::Concern
          step :risky
          def risky(n:)
            raise RuntimeError, "bad n=#{n}"
          end
        end

        result = svc.new.run_steps(starting_data: { n: 7 }, rescue_errors: true)
        expect(result).to be_a(Flowy::Failure)
        expect(result.error_code).to eq(:step_raised_error)
        expect(result.error_data[:message]).to eq('bad n=7')
      end
    end
  end
end
