# Flowy

**Flowy** is a lightweight Ruby gem for building clean, composable service objects using the Result pattern (also known as Railway Oriented Programming).

Instead of raising exceptions or returning `true`/`false`, your service methods return typed `Success` or `Failure` objects that carry data or error information.

## Installation

Add to your Gemfile:

```ruby
gem 'flowy'
```

## Core objects

### `Flowy::Success`

Represents a successful outcome. Carries a `data` hash (the result payload) and an optional `warnings` array.

```ruby
result = Flowy::Success.new(data: { user_id: 1 }, warnings: ['email not verified'])

result.success?       # => true
result.failure?       # => false
result.data           # => { user_id: 1 }
result.warnings       # => ['email not verified']
result.to_hash
# => { success: true, data: { user_id: 1 }, warnings: ['email not verified'] }
```

You can also build one via the factory:

```ruby
Flowy::Result.success(data: { id: 1 })
```

#### Merging two successes

`+` performs a deep merge of the `data` hashes:

```ruby
a = Flowy::Success.new(data: { x: 1, meta: { a: 1 } })
b = Flowy::Success.new(data: { y: 2, meta: { b: 2 } })
(a + b).data  # => { x: 1, y: 2, meta: { a: 1, b: 2 } }
```

#### `merge_data`

Returns a **new** `Success` with data deep-merged. Accepts either a hash or a block receiving the current data:

```ruby
result.merge_data(role: :admin)
result.merge_data { |d| { count: d[:items].size } }
```

---

### `Flowy::Failure`

Represents a failed outcome. Carries a typed `error_code` symbol and optional contextual fields.

```ruby
result = Flowy::Failure.new(
  error_code:        :payment_declined,
  error_data:        { gateway: 'stripe', amount: 99 },
  error_title:       'Payment declined',
  error_description: 'The card was declined by the issuer'
)

result.failure?           # => true
result.success?           # => false
result.error_code         # => :payment_declined
result.error_data         # => { gateway: 'stripe', amount: 99 }
result.error_title        # => 'Payment declined'
result.error_description  # => 'The card was declined by the issuer'
result.to_hash
# => { success: false, error_code: :payment_declined, error_data: {...},
#      error_title: 'Payment declined', error_description: '...' }
```

You can also build one via the factory:

```ruby
Flowy::Result.failure(error_code: :not_found, error_title: 'Not Found')
```

#### `merge_data`

Returns a **new** `Failure` with `error_data` deep-merged. All other attributes (including `parent_failure`) are preserved:

```ruby
result.merge_data(context: 'CreateUser')
result.merge_data { |d| d.merge(retryable: false) }
```

#### `is?` — error_code predicate

Convenience predicate for matching `error_code`. Equivalent to `failure.error_code == code` but reads as a sentence at the call site:

```ruby
failure = Flowy::Failure.new(error_code: :not_found)

failure.is?(error_code: :not_found)  # => true
failure.is?(error_code: :other)      # => false
```

#### Chaining nested failures with `parent_failure`

When a service wraps a failure from a downstream service, set `parent_failure:` to preserve the full error history:

```ruby
inner = Flowy::Failure.new(error_code: :stripe_error)
outer = Flowy::Failure.new(error_code: :charge_failed, parent_failure: inner)

outer.failures_chain  # => [inner, outer]
```

`failures_chain` traverses the chain from root to leaf, giving you the complete error trail for logging or debugging.

#### Raising a failure as an exception with `raise!`

Convert a `Failure` into a `Flowy::Error` and raise it. Useful when a failure must propagate through code that does not handle results (e.g. a callback, a background job framework, or a boundary where exceptions are expected):

```ruby
result = PaymentService.new.call(data)
result.raise!
# => raises Flowy::Error (code: :payment_declined, title: '...', detail: '...', meta: {...})
```

The raised `Flowy::Error` is a `StandardError`, so it can be rescued normally:

```ruby
begin
  PaymentService.new.call(data).raise!
rescue Flowy::Error => e
  e.code    # => :payment_declined
  e.to_failure  # => back to a Flowy::Failure
end
```

`raise!` is a **no-op on `Success`** — it returns `self` unchanged, making it safe to attach unconditionally:

```ruby
ServiceB.new.call(data)
  .raise!                            # raises only if Failure
  .and_then { |r| do_more(r.data) }  # continues only if Success
```

#### Wrapping failures from nested services with `map_failure`

When service A calls service B, you can translate B's failure into A's own vocabulary while automatically preserving the original as `parent_failure`:

```ruby
# Block form — full control
PaymentService.new.call(data)
  .map_failure { |f|
    Flowy::Failure.new(
      error_code:        :charge_failed,
      error_data:        { reason: f.error_code },
      error_description: 'Payment could not be completed'
      # parent_failure is set automatically when omitted
    )
  }

# Shorthand form — no block needed
PaymentService.new.call(data)
  .map_failure(error_code: :charge_failed, error_data: { source: :payment_service })
```

`map_failure` is a **no-op on `Success`** — it returns `self` unchanged, making it safe to attach unconditionally:

```ruby
ServiceB.new.call(data)
  .map_failure(error_code: :service_b_failed)
  .and_then { |r| success(data: r.data.merge(done: true)) }
  .on_failure { |r| puts r.failures_chain.map(&:error_code).inspect }
  # => [:original_b_error, :service_b_failed]
```

---

### `Flowy::Error`

A `StandardError` subclass that bridges Flowy's result objects with Ruby's exception system. Use it when you need to raise an exception carrying the same structured data as a `Failure`.

```ruby
error = Flowy::Error.new(
  code:   :payment_declined,
  title:  'Payment declined',
  detail: 'The card was declined by the issuer',
  meta:   { gateway: 'stripe' }
)

raise error
```

`Flowy::Error` is also rescuable as a standard `StandardError`.

#### Building from a `Failure`

```ruby
failure = Flowy::Failure.new(
  error_code:        :not_found,
  error_title:       'Not found',
  error_description: 'Record does not exist',
  error_data:        { id: 42 }
)

error = Flowy::Error.initialize_from_failure(failure: failure)
error.code    # => :not_found
error.title   # => 'Not found'
error.detail  # => 'Record does not exist'
error.meta    # => { id: 42 }
```

#### Converting back to a `Failure`

```ruby
error.to_failure  # => Flowy::Failure
error.to_hash     # => same structure as Failure#to_hash
```

---

### `Flowy::Result` — the union type

Both `Success` and `Failure` include `Flowy::Result`, enabling uniform type-checking:

```ruby
result.is_a?(Flowy::Result)  # => true for both Success and Failure
```

Factory methods:

```ruby
Flowy::Result.success(data: { id: 1 })
Flowy::Result.failure(error_code: :not_found, error_title: 'Not Found')
```

#### `Result.wrap` — adapter for exception-raising code

Executes a block and automatically converts its outcome into a `Success` or `Failure`. Useful for integrating third-party libraries or any code that raises exceptions:

```ruby
# Plain value → Success(data: { value: <User> })
result = Flowy::Result.wrap { User.find(id) }

# Existing Success/Failure → forwarded unchanged
result = Flowy::Result.wrap { some_service.call }

# Custom error_code and rescue classes
result = Flowy::Result.wrap(
  rescue:      [ActiveRecord::RecordNotFound],
  error_code:  :not_found,
  error_title: 'Resource not found'
) { User.find(id) }

result.on_success { |r| puts r.data[:value] }
      .on_failure { |r| puts r.error_code }  # => :not_found
```

On failure the generated `Flowy::Failure` contains:
- `error_code` — `:wrapped_error` by default or the value passed via `error_code:`
- `error_data` — `{ error_class: '...', message: '...' }`
- `error_description` — the exception message

---

### Shared result methods

Both `Success` and `Failure` share the following chainable interface:

#### `on_success` / `on_failure`

Yields `self` only when the type matches; always returns `self`:

```ruby
OrderService.new.call
  .on_success { |r| render json: r.data }
  .on_failure { |r| render json: r.to_hash, status: :unprocessable_entity }
```

#### `and_then` / `or_else`

`and_then` pipes a `Success` into the next step; short-circuits on `Failure`:

```ruby
validate(params)
  .and_then { |r| persist(r.data) }
  .and_then { |r| notify(r.data) }
```

`or_else` is the symmetric counterpart — runs only on `Failure`, allowing recovery:

```ruby
fetch_from_cache(id)
  .or_else { fetch_from_db(id) }
```

Both methods require the block to return a `Flowy::Success` or `Flowy::Failure`.

#### `tap`

Yields `self` for side-effects (logging, telemetry) without modifying it:

```ruby
OrderService.new.call
  .tap        { |r| Rails.logger.info(r.to_hash) }
  .on_success { |r| render json: r.data }
  .on_failure { |r| render json: r.to_hash, status: :unprocessable_entity }
```

---

## Service objects with `Flowy::Concern`

Include `Flowy::Concern` in any class to get `success`, `failure`, and `run_steps`:

```ruby
class OrderService
  include Flowy::Concern

  def call
    run_steps(
      starting_data: { order_id: 42 },
      steps: [:validate, :reserve_stock, :charge_payment]
    )
  end

  private

  def validate(previous_result:)
    return failure(error_code: :invalid_order) unless valid?
    success(data: previous_result.data)
  end

  def reserve_stock(previous_result:)
    success(data: previous_result.data.merge(reserved: true))
  end

  def charge_payment(previous_result:)
    success(data: previous_result.data.merge(charged: true))
  end
end
```

### Step pipeline with `run_steps`

`run_steps` executes an ordered list of steps sequentially. Each step must return a `Success` or `Failure`. The pipeline short-circuits as soon as any step returns a `Failure`.

Steps can be:
- **Symbol** — name of an instance method on the service
- **Lambda / Proc** — any callable that accepts `previous_result:`

#### Step method signatures

Flowy inspects the keyword parameters declared by each step method and builds the call arguments automatically. You can choose the style that best communicates the method's contract:

```ruby
# 1. Classic — receives the full result object
def persist(previous_result:)
  user = User.create!(previous_result.data[:params])
  success(data: { user: user })
end

# 2. Data-keys — declares exactly which data keys it needs (self-documenting)
def notify(user:)
  UserMailer.welcome(user).deliver_later
  success
end

# 3. Mixed — data keys + full result when both are needed
def charge(order_id:, amount:, previous_result:)
  # use order_id and amount directly; inspect previous_result.warnings if needed
  success(data: previous_result.data.merge(charged: true))
end

# 4. With ** rest — captures any remaining data keys not declared explicitly
def forward(required_key:, **rest)
  success(data: rest.merge(required_key: required_key))
end
```

**Required vs optional keyword parameters**

- `keyreq` (e.g. `def step(n:)`) — Flowy raises an `ArgumentError` with a descriptive message if the key is absent from `result.data`.
- `key` with a default (e.g. `def step(label: 'default')`) — Flowy passes the value only when the key exists in `result.data`; otherwise Ruby uses the declared default.

**Reserved keyword: `previous_result`**

`previous_result` is a reserved parameter name. When a step method declares `previous_result:`, Flowy always passes the full `Flowy::Result` object, regardless of whether `previous_result` exists as a key in `result.data`. Avoid using `:previous_result` as a data key — it will be shadowed by the Result object (or, if the step does not declare `previous_result:`, will leak into the `**rest` hash).

```ruby
class CreateUser
  include Flowy::Concern

  def call(params)
    run_steps(
      starting_data: { params: params },
      steps: [:validate, :persist, :notify],
      rescue_errors: true   # converts uncaught exceptions to Failure
    )
  end

  private

  def validate(params:)               # receives params directly from data
    return failure(error_code: :invalid_params) if params.empty?
    success(data: { params: params })
  end

  def persist(params:)                # only needs params
    user = User.create!(params)
    success(data: { user: user })
  end

  def notify(user:, previous_result:) # data key + full result
    UserMailer.welcome(user).deliver_later
    success(data: previous_result.data)
  end
end
```

### Declarative step pipeline with `.step` / `.tap_step`

Steps can be declared at class level. `run_steps` uses them automatically when no explicit `steps:` array is passed:

```ruby
class CreateUser
  include Flowy::Concern

  step :validate
  tap_step :log_audit     # side-effect only; return value is ignored
  step :persist
  step :notify

  def call(params)
    run_steps(starting_data: { params: params })
  end

  private

  def log_audit(**data)   # receives all data keys via **rest
    Rails.logger.info("[CreateUser] #{data.keys}")
    # no need to return a result
  end

  # ... other step methods
end
```

### Granular exception handling with `rescue:` / `on_error:`

Declare which exception classes a step can raise and how to handle them:

```ruby
step :persist, rescue: [ActiveRecord::RecordInvalid], on_error: :handle_db_error

# Without on_error, the exception is converted to a generic Failure:
step :persist, rescue: [ActiveRecord::RecordInvalid]
# => error_code: :step_raised_error, error_data: { step: :persist, message: '...' }

def handle_db_error(error, previous_result:)
  failure(
    error_code: :persistence_failed,
    error_data: { message: error.message, params: previous_result.data[:params] }
  )
end
```

### Step hooks: `before_step`, `after_step`, `around_step`

Flowy provides three composable hook types that fire around every step execution without touching the step implementations themselves.

| Hook | Fires | Can modify result? | Block signature |
|---|---|---|---|
| `before_step` | just **before** the step | ✗ side-effect only | `\|step_name, previous_result\|` |
| `after_step` | just **after** the step | ✗ side-effect only | `\|step_name, result\|` |
| `around_step` | **wraps** the step | ✓ must return a `Flowy::Result` | `\|step_name, previous_result, &call\|` |

Hooks can be registered at three scopes, applied in this order per step:

```
global before  →  class before  →  per-step before
  global around [ class around [ per-step around [ step ] ] ]
per-step after  →  class after  →  global after
```

#### 1. Global hooks — `Flowy::Concern.<hook>`

Run for **every** service class that includes `Flowy::Concern`. Ideal for cross-cutting concerns such as tracing, metrics, and audit logging.

```ruby
# config/initializers/flowy.rb
Flowy::Concern.before_step do |step_name, previous_result|
  Current.audit_log << { step: step_name, at: Time.now }
end

Flowy::Concern.after_step do |step_name, result|
  StatsD.increment("flowy.#{step_name}.#{result.success? ? 'success' : 'failure'}")
end

Flowy::Concern.around_step do |step_name, previous_result, &call|
  OpenTelemetry::Tracer.in_span("flowy.#{step_name}") { call.() }
end
```

Remove all global hooks (e.g. in test teardowns):

```ruby
Flowy::Concern.clear_global_hooks!
```

#### 2. Class-level hooks — declared inside the service class

Run only for the service class they are declared on.

```ruby
class CreateUser
  include Flowy::Concern

  before_step do |step_name, previous_result|
    Rails.logger.debug "[CreateUser] starting #{step_name}"
  end

  after_step do |step_name, result|
    Rails.logger.debug "[CreateUser] #{step_name} → #{result.success? ? '✓' : '✗'}"
  end

  around_step do |step_name, previous_result, &call|
    t0 = Time.now
    result = call.()
    Rails.logger.info "[CreateUser] #{step_name} (#{((Time.now - t0) * 1000).round}ms)"
    result
  end

  step :validate
  step :persist
  step :notify
end
```

#### 3. Per-step hooks — inline on `step` / `tap_step`

Scoped to a **single step**. Accept either a **Symbol** (name of an instance method) or any **callable** (lambda / proc).

```ruby
class CreateOrder
  include Flowy::Concern

  step :validate,
    before_step: :log_start                          # Symbol → instance method

  step :charge,
    before_step: ->(name, prev) { Tracer.start(name) },
    after_step:  ->(name, res)  { Tracer.finish(name, res.success?) },
    around_step: :enforce_idempotency

  step :persist,
    rescue:      [ActiveRecord::RecordInvalid],
    on_error:    :handle_db_error,
    after_step:  ->(name, res) { Rails.logger.info "persist: #{res.success?}" }

  tap_step :audit_trail,
    before_step: ->(name, _prev) { AuditLog.open(name) },
    after_step:  ->(name, _res)  { AuditLog.close(name) }

  private

  def log_start(step_name, previous_result)
    Rails.logger.info "Starting #{step_name}"
  end

  def enforce_idempotency(step_name, previous_result, &call)
    IdempotencyGuard.wrap(step_name) { call.() }
  end

  # ...
end
```

Per-step `around_step` can also short-circuit by returning a `Failure` without calling `call.()`:

```ruby
step :charge, around_step: ->(name, prev, &_call) {
  return Flowy::Result.failure(error_code: :dry_run) if DryRun.active?
  _call.()
}
```

#### Notes

- `after_step` receives `previous_result` (not the step's raw return) for `tap_step`s, because tap-steps always forward the previous result.
- Multiple hooks of the same scope and type run in **registration order**.
- `around_step` blocks **must** return a `Flowy::Result`; a `TypeError` is raised otherwise.

---

## `Flowy::Pipeline` — composable pipelines as first-class objects

`Flowy::Pipeline` is an **immutable, composable** pipeline that lives outside any service class. It can be built with a fluent DSL, stored as a constant, passed as a value, composed with `>>`, and embedded inside a `Flowy::Concern`.

### Linear pipeline

```ruby
PROCESS = Flowy::Pipeline.new
  .step(:validate)  { |prev| ValidateOrder.call(prev.data) }
  .step(:persist)   { |prev| PersistOrder.call(prev.data) }
  .step(:notify)    { |prev| NotifyUser.call(prev.data) }

result = PROCESS.call(starting_data: { order_id: 42 })
```

### Symbolic steps — resolved against a `context:`

A `step` can also be declared as a bare Symbol without a block. At execution time the method is resolved against the `context:` object passed to `#call`. The resolved method must accept `previous_result:` and return a `Flowy::Result`.

```ruby
PROCESS = Flowy::Pipeline.new
  .step(:validate)
  .step(:persist)
  .step(:notify)

class OrderService
  def validate(previous_result:); ...; end
  def persist(previous_result:);  ...; end
  def notify(previous_result:);   ...; end
end

PROCESS.call(starting_data: { order_id: 42 }, context: OrderService.new)
```

Calling a symbolic-step pipeline without a `context:` raises `ArgumentError`. Symbolic and block steps can be freely mixed in the same pipeline.

### `tap_step` — side-effects without altering the flow

```ruby
pipeline = Flowy::Pipeline.new
  .step(:persist)   { |prev| PersistOrder.call(prev.data) }
  .tap_step(:audit) { |prev| AuditLog.record(prev.data) }   # return value is ignored
  .step(:notify)    { |prev| NotifyUser.call(prev.data) }
```

### Conditional branching

Dispatches to a different sub-pipeline based on a key in `previous_result.data` (or the return value of a lambda).

#### Dispatch via Symbol key

```ruby
PAYMENT = Flowy::Pipeline.new
  .step(:reserve) { |prev| ReserveStock.call(prev.data) }
  .branch(on: :payment_method) do |b|
    b.when(:stripe)  { Flowy::Pipeline.new.step(:charge) { |p| StripeCharge.call(p.data) } }
    b.when(:paypal)  { Flowy::Pipeline.new.step(:charge) { |p| PayPalCharge.call(p.data) } }
    b.otherwise      { Flowy::Pipeline.new.step(:charge) { |p| DefaultCharge.call(p.data) } }
  end
  .step(:notify) { |prev| NotifyUser.call(prev.data) }

result = PAYMENT.call(starting_data: { order_id: 1, payment_method: :stripe })
```

`on: :payment_method` reads `previous_result.data[:payment_method]` and routes to the matching branch. If no branch matches and `otherwise` is not defined, a `Failure` with `error_code: :unmatched_branch` is returned.

#### Dispatch via Lambda (arbitrary logic)

```ruby
.branch(on: ->(data) { data[:amount] > 1000 ? :high_value : :standard }) do |b|
  b.when(:high_value) { Flowy::Pipeline.new.step(:premium_flow) { |p| ... } }
  b.when(:standard)   { Flowy::Pipeline.new.step(:normal_flow)  { |p| ... } }
end
```

### Composition with `>>`

Concatenates two or more pipelines into a new immutable pipeline:

```ruby
CHECKOUT    = Flowy::Pipeline.new.step(:validate) { ... }.step(:reserve) { ... }
PAYMENT     = Flowy::Pipeline.new.step(:charge)   { ... }
FULFILLMENT = Flowy::Pipeline.new.step(:ship)     { ... }.step(:notify) { ... }

FULL_ORDER = CHECKOUT >> PAYMENT >> FULFILLMENT

result = FULL_ORDER.call(starting_data: { order_id: 42 })
```

### Integration with `Flowy::Concern`

A `Flowy::Pipeline` can be used directly as a step, both inline in `run_steps` and in the `.step` DSL:

```ruby
SUB_PIPELINE = Flowy::Pipeline.new
  .step(:enrich) { |prev| EnrichData.call(prev.data) }

# Inline
class OrderService
  include Flowy::Concern

  def call
    run_steps(
      starting_data: { order_id: 1 },
      steps: [SUB_PIPELINE, :notify]
    )
  end
end

# Via DSL
class OrderService
  include Flowy::Concern

  step SUB_PIPELINE
  step :notify

  def call = run_steps(starting_data: { order_id: 1 })
end
```

### Introspection

```ruby
pipeline.steps
# => [
#   { type: :step,   name: :validate },
#   { type: :branch, name: :"branch(payment_method)", on: :payment_method, branches: {...}, otherwise: [...] },
#   { type: :step,   name: :notify }
# ]

pipeline.size   # => 3
pipeline.empty? # => false
```

### `#call` options

| Option | Type | Default | Description |
|---|---|---|---|
| `starting_data` | Hash | `{}` | Initial data wrapped in a `Success` |
| `rescue_errors` | Boolean | `false` | Converts uncaught `StandardError`s into a `Failure` with `error_code: :step_raised_error` |
| `context` | Object | `nil` | Optional object passed to the block as a second argument (useful when the pipeline is embedded inside a service instance) |

---

## API reference

### `Flowy::Success`
| Method | Description |
|---|---|
| `data` | Hash with result payload |
| `warnings` | Array of warning messages |
| `success?` | Always `true` |
| `failure?` | Always `false` |
| `to_hash` | Serialized result |
| `+(other)` | Deep-merges two `Success` objects |
| `on_success` { \|result\| } | Yields `self` and returns `self`; no-op on `Failure` |
| `on_failure` { } | No-op on `Success`; yields on `Failure` |
| `and_then` { \|result\| } | Yields `self`, returns the block's result; no-op on `Failure` |
| `or_else` { } | No-op on `Success`; yields on `Failure` |
| `merge_data(hash)` / `merge_data { }` | Returns a new `Success` with data deep-merged |
| `map_failure` / `map_failure(error_code:, ...)` | No-op on `Success` |
| `raise!` | No-op on `Success`; raises `Flowy::Error` on `Failure` |
| `tap` { \|result\| } | Yields `self` for side-effects; always returns `self` unchanged |

### `Flowy::Failure`
| Method | Description |
|---|---|
| `error_code` | Symbol identifying the error |
| `error_data` | Hash with contextual error data |
| `error_title` | Optional human-readable title |
| `error_description` | Optional human-readable description |
| `parent_failure` | Optional link to the originating failure |
| `success?` | Always `false` |
| `failure?` | Always `true` |
| `to_hash` | Serialized result |
| `failures_chain` | Array of chained failures from root to leaf |
| `is?(error_code:)` | `true` if `self.error_code == error_code` |
| `on_failure` { \|result\| } | Yields `self` and returns `self`; no-op on `Success` |
| `on_success` { } | No-op on `Failure`; yields on `Success` |
| `or_else` { \|result\| } | Yields `self`, returns the block's result; no-op on `Success` |
| `and_then` { } | No-op on `Failure`; yields on `Success` |
| `merge_data(hash)` / `merge_data { }` | Returns a new `Failure` with `error_data` deep-merged |
| `map_failure { \|f\| }` | Transforms `self` into a new `Failure`; sets `parent_failure: self` automatically |
| `map_failure(error_code:, error_data:, error_title:, error_description:)` | Shorthand — builds the wrapping `Failure` without a block |
| `raise!` | Raises a `Flowy::Error` built from `self`; no-op on `Success` |
| `tap` { \|result\| } | Yields `self` for side-effects; always returns `self` unchanged |

### `Flowy::Error`
| Method / attribute | Description |
|---|---|
| `code` | Symbol identifying the error (maps to `error_code`) |
| `title` | Optional human-readable title |
| `detail` | Optional human-readable description |
| `meta` | Optional hash with contextual data |
| `.initialize_from_failure(failure:)` | Builds a `Flowy::Error` from a `Flowy::Failure` |
| `#to_failure` | Converts back to a `Flowy::Failure` |
| `#to_hash` | Same structure as `Failure#to_hash` |

### `Flowy::Result`
| Method | Description |
|---|---|
| `Result.success(data:, warnings:)` | Factory — builds a `Flowy::Success` |
| `Result.failure(error_code:, error_data:, error_title:, error_description:, parent_failure:)` | Factory — builds a `Flowy::Failure` |
| `Result.wrap(rescue:, error_code:, error_title:) { }` | Wraps block outcome; forwards existing result objects unchanged |

### `Flowy::Concern`

**Instance helpers:**

- `success(data:, warnings:)`
- `failure(error_code:, error_data:, error_title:, error_description:)`
- `run_steps(starting_data:, steps:, rescue_errors: false)`

**Class-level DSL:**

| Macro | Description |
|---|---|
| `step :name` | Registers a step in the class pipeline |
| `step :name, rescue: [ExcClass], on_error: :handler` | Step with granular exception handling |
| `step :name, before_step: :method_or_lambda` | Per-step before-hook (Symbol or callable) |
| `step :name, after_step: :method_or_lambda` | Per-step after-hook (Symbol or callable) |
| `step :name, around_step: :method_or_lambda` | Per-step around-hook (Symbol or callable) |
| `tap_step :name` | Side-effect step; also accepts `before_step:`, `after_step:`, `around_step:` |
| `before_step { \|step_name, previous_result\| }` | Class-level before-hook (all steps) |
| `after_step { \|step_name, result\| }` | Class-level after-hook (all steps) |
| `around_step { \|step_name, previous_result, &call\| }` | Class-level around-hook (all steps) |

**Module-level (global) DSL:**

| Method | Description |
|---|---|
| `Flowy::Concern.before_step { \|step_name, previous_result\| }` | Global before-hook for all service classes |
| `Flowy::Concern.after_step { \|step_name, result\| }` | Global after-hook for all service classes |
| `Flowy::Concern.around_step { \|step_name, previous_result, &call\| }` | Global around-hook for all service classes |
| `Flowy::Concern.clear_global_hooks!` | Removes all global hooks (before, after, around) |

**`run_steps` options:**

| Option | Type | Default | Description |
|---|---|---|---|
| `starting_data` | Hash | `{}` | Initial data wrapped in a `Success` |
| `steps` | Array\|nil | `nil` | Explicit step list (overrides class DSL when provided) |
| `rescue_errors` | Boolean | `false` | When `true`, converts uncaught `StandardError`s to a `Failure` with `error_code: :step_raised_error` |

**Step method keyword dispatch:**

Flowy inspects each Symbol step method's declared keyword parameters and builds the call accordingly:

| Parameter type | Behaviour |
|---|---|
| `previous_result:` | Receives the full `Flowy::Result` object |
| `key:` (required, no default) | Resolved from `result.data[key]`; raises `ArgumentError` if the key is absent |
| `key: default` (optional) | Resolved from `result.data[key]` when present; otherwise Ruby uses the declared default |
| `**rest` | Receives all remaining data keys not declared explicitly |

### `Flowy::Pipeline`

| Method | Description |
|---|---|
| `#step(name) { \|prev\| }` | Appends a step; the block must return a `Flowy::Result` |
| `#step(:name)` (no block) | Appends a symbolic step resolved against `context:` at call time; the method must accept `previous_result:` |
| `#tap_step(name) { \|prev\| }` | Appends a side-effect step; the return value is ignored |
| `#branch(on:) { \|b\| }` | Appends a branch node; `on:` is a Symbol or Lambda |
| `#>>(other)` | Composes two pipelines sequentially; returns a new Pipeline |
| `#call(starting_data:, rescue_errors:, context:)` | Executes the pipeline |
| `#steps` | Returns the step list for introspection |
| `#size` | Number of top-level steps (including branch nodes) |
| `#empty?` | `true` when there are no steps |

---

## License

MIT
