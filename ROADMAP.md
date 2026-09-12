# BWF Project Roadmap

Central task tracker for the planned release road stages.

---

## Milestone 1: Core Engine & Hook Pipeline

- [ ] **Strict Hook System Upgrades**
  - [ ] **1. Scope collision:** Fail-fast at registration if a duplicate hook ID is registered in the same phase on the same scope (`App`, `Routes`, or `Endpoint`).
  - [ ] **2. Tree shadowing:** Prohibit child scopes (`Routes`/`Endpoint`) from silently shadowing ancestor hook IDs in the same phase.
  - [ ] **3. Explicit override API:** Implement `scope:overrideHook(phase, hook)` to intentionally replace an ancestor hook for a subtree or endpoint.
  - [ ] **4. Explicit opt-out API:** Implement `scope:disableHook(phase, hook_id)` to exempt specific endpoints/routes from inherited hooks.
  - [ ] **5. ID format & namespacing:** Validate hook ID strings (`group:name`) and reserve `bwf:` prefix for core framework hooks.
  - [ ] **6. Pre-compiled hook chains:** Flatten and validate active hooks per endpoint during route compilation (`App:compilePaths`), eliminating runtime traversal lookups.
  - [ ] **7. Hook observability:** Attribute execution metrics and pipeline errors with the active hook ID in logs and error details.
- [ ] **Server Lifecycle & Control Flow**
  - [ ] Implement `App.run()` that yields execution (via coroutine) until the server is stopped, keeping `App:start()` explicitly asynchronous/non-blocking.
  - [ ] Update `App.port` after `:listen` when assigned port `0` (ephemeral/random port).
- [ ] **Request Safeguards & Limits**
  - [ ] Request body size limits with early rejection before unbounded memory buffering (return `413 Content Too Large`).
  - [ ] Per-route / per-app configurable payload limits.

---

## Milestone 2: Protocol & Security Foundation

- [ ] **HTTP/2 & HTTP/3 Future Compatibility**
  - [ ] **Connection headers:** Remove hardcoded `Connection: close` in `Call:abort` and `App:_panic`; let the adapter layer manage connection teardown semantics (connection-specific headers are illegal in H2/H3).
  - [ ] **Stream vs Connection abort:** Ensure `Adapter:abort` treats `Call` as a logical stream (triggering `RST_STREAM` in H2/H3 vs TCP RST in H1).
  - [ ] **Streaming abstraction:** Design future body streaming around iterators/chunks without exposing HTTP/1.1 `Transfer-Encoding: chunked`.
- [ ] **Connection & Socket Management**
  - [ ] Socket lifecycle and idle timeout management (disconnect stale/hung connections).
  - [ ] Slowloris & minimum transfer rate protection: automatically terminate connections that trickle data below a minimum byte threshold.
  - [ ] Connection keep-alive limits.
- [ ] **Traffic & Bandwidth Controls**
  - [ ] Bandwidth throttling support: opt-in token-bucket rate limiter for file downloads and streaming responses (e.g. `call:file(path, { throttle = '500kb/s' })` or `bwf:throttle` hook).
  - [ ] Rate-limiting hooks (`bwf:ratelimit` per IP / per API key).
- [ ] **Standard Security Hooks**
  - [ ] CORS hook (`bwf:cors`) with origin, headers, credentials, and preflight `OPTIONS` handling.
  - [ ] Security headers hook (`bwf:security_headers`): `HSTS`, `X-Content-Type-Options: nosniff`, `X-Frame-Options`, `Content-Security-Policy`.

---

## Milestone 3: Authentication & Identity (Porting `weblit-auth`)

- [ ] **Port `weblit-auth` to BWF Hook Architecture**
  - [ ] Bearer token / JWT authentication hook (`auth:bearer`).
  - [ ] Session cookie authentication hook (`auth:session`).
  - [ ] Basic authentication hook (`auth:basic`).
  - [ ] Password hashing utilities (Argon2 / bcrypt).
- [ ] **Context & State Integration**
  - [ ] Standardize authenticated user identity on `call.state.user`.
  - [ ] Return RFC 9457 Problem Details (`401 Unauthorized`, `403 Forbidden`) via `call:problem()` on auth failures.
  - [ ] Role-based access control (RBAC) / permission check hooks.

---

## Milestone 4: Observability & Core Utilities

- [ ] **Structured Logging Subsystem**
  - [ ] Core `Logger` instance with configurable log levels (`TRACE`, `DEBUG`, `INFO`, `WARN`, `ERROR`, `FATAL`).
  - [ ] Child logger support (`logger:child{ ... }`) inheriting parent configuration while attaching request metadata (`req_id`, `ip`, `method`, `path`).
  - [ ] Pluggable formatters (JSON for production/log aggregation, pretty ANSI colors for development).
- [ ] **Network & IP Utilities**
  - [ ] Client IP extraction supporting `X-Forwarded-For`, `X-Real-IP`, and RFC 7239 `Forwarded` headers with trusted proxy subnet filtering.
- [ ] **Localization (i18n)**
  - [ ] Accept-Language parsing and locale negotiation.
  - [ ] Localized problem details and response messaging.

---

## Milestone 5: Developer Experience & Contracts

- [ ] **Fluent Builders**
  - [ ] `bwf.builder.operation` for fluent endpoint/operation definition.
  - [ ] `bwf.builder.problem` for fluent RFC 9457 Problem Details creation.
- [ ] **OpenAPI 3.x Serialization**
  - [ ] Auto-generate OpenAPI 3.0/3.1 JSON/YAML schema from registered `Endpoint`, `Parameters`, and `Responses` definitions.
  - [ ] Built-in interactive documentation UI route (Swagger UI / Scalar / Redoc).
- [ ] **Schema & Type Validation**
  - [ ] Request body, query string, and path parameter validation against schemas with automatic 422/400 Problem Details.

---

## Post-1.0 / Future Architecture

- [ ] **Native HTTP/1.1 Engine**
  - [ ] Replace `weblit-server` dependency with a native, zero-dependency libuv HTTP/1.1 streaming parser.
- [ ] **Native HTTP/2 Adapter**
  - [ ] Bind `libnghttp2` (via LuaJIT FFI or C bindings) for native multiplexed HTTP/2 support with ALPN TLS.
- [ ] **Database & Storage Utilities**
  - [ ] Connection pooling helpers and ORM/query builder integrations.
