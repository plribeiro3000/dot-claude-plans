# Migration Plan: 4Shark SDK .NET to AdvPL

## Overview

This plan covers the complete migration of the 4Shark SDK from .NET to AdvPL for Protheus integration.

**Source:** `app-sdk-dotnet` (version 1.0.0 + Orchestration)
**Target:** `app-sdk-advpl`

## Analysis Summary

### .NET SDK Components to Migrate

| Category | Files | Complexity |
|----------|-------|------------|
| Core | 5 files | High |
| Resources | 18 files | Medium |
| Orchestration | 5 files | High |
| Documentation | 12 files | Low |
| Examples | 1 project | Medium |
| **Total** | **41 items** | - |

### AdvPL Technical Considerations

| Aspect | .NET | AdvPL Equivalent |
|--------|------|------------------|
| HTTP Client | HttpClient | HttpGet/HttpPost/HttpPut/HttpDelete |
| JSON | System.Text.Json | JsonObject/JsonArray (native) |
| Async/Await | Task<T> | Synchronous calls |
| Classes | C# classes | Class...EndClass |
| Generics | Yes | No (use dynamic types) |
| Naming | Unlimited | 10 chars (AdvPL) / 255 chars (TL++) |
| Logging | ILogger | ConOut/LogExec |

### Target Audience

- Protheus on-premise (older versions)
- Use **pure AdvPL** (not TL++) for maximum compatibility
- **Minimum version: Protheus 11**

### Key Decisions

| Decision | Value | Rationale |
|----------|-------|-----------|
| Minimum Version | Protheus 11 | Covers ~15 years of installations |
| Distribution | Source files (.prw) via GitHub | No PTM - client compiles in their RPO |
| Configuration | SX6 (primary) + INI (fallback) | Standard Protheus patterns |
| Documentation | English only | Industry standard |
| HTTP | HttpGet/HttpPost (not FWRest) | FWRest requires P12+ |

---

## Phase 1: Project Setup

### 1.1 Repository Structure

```
app-sdk-advpl/
├── README.md                    # Installation and usage guide
├── CHANGELOG.md                 # Version history
├── LICENSE                      # MIT License
├── src/
│   ├── 4SharkSDK.prw           # Main SDK client (entry point)
│   ├── 4SharkOpt.prw           # Client options/configuration
│   ├── 4SharkReq.prw           # HTTP request handler
│   ├── 4SharkRes.prw           # API response wrapper
│   ├── 4SharkExc.prw           # Exception/error handling
│   └── resources/
│       ├── 4SKClient.prw       # Client resource
│       ├── 4SKCliAct.prw       # Client activity
│       ├── 4SKDeal.prw         # Deal resource
│       ├── 4SKDealAct.prw      # Deal activity
│       ├── 4SKDealFld.prw      # Deal field
│       ├── 4SKGoal.prw         # Goal resource
│       ├── 4SKGroup.prw        # Group resource
│       ├── 4SKGrpAct.prw       # Group activity
│       ├── 4SKGrpfct.prw       # Groupification
│       ├── 4SKIndic.prw        # Indicator resource
│       ├── 4SKProd.prw         # Product resource
│       ├── 4SKProdAct.prw      # Product activity
│       ├── 4SKSubsid.prw       # Subsidiary resource
│       ├── 4SKSubAct.prw       # Subsidiary activity
│       ├── 4SKUser.prw         # User resource
│       ├── 4SKUsrAct.prw       # User activity
│       ├── 4SKUsrFld.prw       # User field
│       └── 4SKUsrId.prw        # User identifier
├── orchestration/
│   ├── 4SKOrch.prw             # Orchestration base
│   ├── 4SKExecPl.prw           # Execution plan
│   ├── 4SKOrStep.prw           # Orchestration step
│   └── 4SKUsrTrf.prw           # User subsidiary transfer
├── examples/
│   ├── BasicUsage.prw          # Basic usage example
│   ├── DealCreate.prw          # Deal creation example
│   └── UserTransfer.prw        # User transfer orchestration
└── docs/
    ├── INSTALLATION.md         # Step-by-step installation guide
    ├── RESOURCES.md            # API resources documentation
    ├── REFERENCE_VALUES.md     # Value types reference
    ├── BEST_PRACTICES.md       # Integration best practices
    └── USE_CASES.md            # Practical use cases
```

### 1.2 Naming Convention

Due to AdvPL's 10-character limit for function names:

| Pattern | Example |
|---------|---------|
| Main SDK | `4Shark*` |
| Resources | `4SK*` |
| Methods | `<Resource><Action>` |

### 1.3 Tasks

- [ ] Create initial repository structure
- [ ] Create README.md with installation instructions
- [ ] Create CHANGELOG.md (version 1.0.0)
- [ ] Create LICENSE file (MIT)
- [ ] Create .gitignore for AdvPL projects

---

## Phase 2: Core Components

### 2.1 FourSharkClient (4SharkSDK.prw)

Main SDK entry point with lazy resource initialization.

**Key Methods:**
- `4SharkNew(oOptions)` - Constructor
- `4SharkHlth(oSelf)` - Health check
- `4SharkCli(oSelf)` - Get Clients resource
- `4SharkProd(oSelf)` - Get Products resource
- `4SharkDeal(oSelf)` - Get Deals resource
- `4SharkUser(oSelf)` - Get Users resource
- (... one method per resource)

**Implementation Notes:**
- Use AdvPL classes or hash arrays for object representation
- Lazy initialization pattern for resources
- Hold reference to HttpClient equivalent

### 2.2 FourSharkClientOptions (4SharkOpt.prw)

Configuration management using Protheus standard patterns.

**Key Methods:**
- `4SKOptNew()` - Constructor with defaults
- `4SKOptVal(oSelf)` - Validate required options
- `4SKOptSX6(cParam)` - Get from SX6 parameters
- `4SKOptINI(cSection, cKey)` - Get from INI file (fallback)

**Configuration Properties:**
- `cBaseUrl` - API base URL (required)
- `cApiKey` - API key (required)
- `cCompany` - Company name (required)
- `cVersion` - API version (default: "v3")
- `nTimeout` - Timeout in seconds (default: 30)

**Configuration Priority:**
1. **SX6 Parameters** (primary - standard Protheus)
2. **INI File** (fallback)

**SX6 Parameters (via GetMV/SuperGetMV):**
- `MV_4SKURL` - API base URL
- `MV_4SKKEY` - API key
- `MV_4SKCOMP` - Company name
- `MV_4SKVER` - API version
- `MV_4SKTOUT` - Timeout in seconds

**INI Configuration (fallback):**
```ini
[FOURSHARK]
BASEURL=https://api.4shark.com/api
APIKEY=your-api-key-here
COMPANY=Your Company Name
VERSION=v3
TIMEOUT=30
```

### 2.3 ApiRequest (4SharkReq.prw)

HTTP request handler with JSON serialization.

**Key Methods:**
- `4SKReqNew(cBaseUrl, cApiKey, cVersion)` - Constructor
- `4SKReqGet(oSelf, cEndpoint)` - GET request
- `4SKReqPost(oSelf, cEndpoint, oData)` - POST request
- `4SKReqPut(oSelf, cEndpoint, oData)` - PUT request
- `4SKReqDel(oSelf, cEndpoint)` - DELETE request

**Implementation Notes:**
- Use `HttpGet()`, `HttpPost()`, `HttpPut()`, `HttpDelete()` native functions
- JSON serialization with `FWJsonSerialize()` or manual build
- Handle response codes and errors
- Add correlation ID header (X-Request-ID)

### 2.4 ApiResponse (4SharkRes.prw)

Response wrapper with status, data, and error information.

**Key Methods:**
- `4SKResNew()` - Constructor
- `4SKResOk(oSelf)` - Check if successful
- `4SKResData(oSelf)` - Get response data
- `4SKResErr(oSelf)` - Get error message
- `4SKResLog(oSelf)` - Get log message

**Properties:**
- `nStatus` - HTTP status code
- `lSuccess` - Success flag
- `oData` - Parsed response data
- `cError` - Error message
- `cRaw` - Raw response body
- `aHeaders` - Response headers

### 2.5 Exception Handling (4SharkExc.prw)

Error handling utilities.

**Key Methods:**
- `4SKExcNew(cMsg, nCode, aErrors)` - Create exception object
- `4SKExcThrow(oExc)` - Throw/log exception
- `4SKExcLog(oExc)` - Log exception details

### 2.6 Tasks

- [ ] Implement 4SharkSDK.prw (main client)
- [ ] Implement 4SharkOpt.prw (configuration)
- [ ] Implement 4SharkReq.prw (HTTP requests)
- [ ] Implement 4SharkRes.prw (response handling)
- [ ] Implement 4SharkExc.prw (error handling)
- [ ] Create unit tests for core components

---

## Phase 3: Resource Implementation

### 3.1 Resource Pattern

Each resource follows the same pattern:

```advpl
// 4SKClient.prw

Static Function 4SKCliNew(oRequest)
    Local oSelf := {}

    AAdd(oSelf, {"oRequest", oRequest})

    Return oSelf

Static Function 4SKCliCrt(oSelf, aAttribs)
    Local oPayload := {}
    Local cEndpoint := ""
    Local oResponse

    // Build payload
    AAdd(oPayload, {"client", aAttribs})

    // Build endpoint
    cEndpoint := oSelf[1][2]:ApiVersion + "/clients"

    // Send request
    oResponse := 4SKReqPost(oSelf[1][2], cEndpoint, oPayload)

    Return oResponse

Static Function 4SKCliUpd(oSelf, cId, aAttribs)
    // ... similar pattern
```

### 3.2 Resources to Implement

| Resource | File | Methods |
|----------|------|---------|
| Client | 4SKClient.prw | Create, Update |
| ClientActivity | 4SKCliAct.prw | Activate, Deactivate |
| Deal | 4SKDeal.prw | Create, Update |
| DealActivity | 4SKDealAct.prw | Activate, Deactivate |
| DealField | 4SKDealFld.prw | Create, Update, Delete |
| Goal | 4SKGoal.prw | CreateGroup, CreateUser, Update |
| Group | 4SKGroup.prw | Create, Update |
| GroupActivity | 4SKGrpAct.prw | Activate, Deactivate |
| Groupification | 4SKGrpfct.prw | Start, Finish |
| Indicator | 4SKIndic.prw | Create, Update, Delete |
| Product | 4SKProd.prw | Create, Update |
| ProductActivity | 4SKProdAct.prw | Activate, Deactivate |
| Subsidiary | 4SKSubsid.prw | Create, Update |
| SubsidiaryActivity | 4SKSubAct.prw | Activate, Deactivate |
| User | 4SKUser.prw | Create, Update |
| UserActivity | 4SKUsrAct.prw | Activate, Deactivate |
| UserField | 4SKUsrFld.prw | Create, Update, Delete |
| UserIdentifier | 4SKUsrId.prw | Create, Delete, Promote |

### 3.3 Tasks

- [ ] Implement Client resource (4SKClient.prw)
- [ ] Implement ClientActivity resource (4SKCliAct.prw)
- [ ] Implement Deal resource (4SKDeal.prw)
- [ ] Implement DealActivity resource (4SKDealAct.prw)
- [ ] Implement DealField resource (4SKDealFld.prw)
- [ ] Implement Goal resource (4SKGoal.prw)
- [ ] Implement Group resource (4SKGroup.prw)
- [ ] Implement GroupActivity resource (4SKGrpAct.prw)
- [ ] Implement Groupification resource (4SKGrpfct.prw)
- [ ] Implement Indicator resource (4SKIndic.prw)
- [ ] Implement Product resource (4SKProd.prw)
- [ ] Implement ProductActivity resource (4SKProdAct.prw)
- [ ] Implement Subsidiary resource (4SKSubsid.prw)
- [ ] Implement SubsidiaryActivity resource (4SKSubAct.prw)
- [ ] Implement User resource (4SKUser.prw)
- [ ] Implement UserActivity resource (4SKUsrAct.prw)
- [ ] Implement UserField resource (4SKUsrFld.prw)
- [ ] Implement UserIdentifier resource (4SKUsrId.prw)

---

## Phase 4: Orchestration

### 4.1 Orchestration Components

Orchestration provides complex multi-step operations with recovery capabilities.

**Files:**
- `4SKOrch.prw` - Base orchestration class
- `4SKExecPl.prw` - Execution plan tracking
- `4SKOrStep.prw` - Individual step management
- `4SKUsrTrf.prw` - User subsidiary transfer implementation

### 4.2 User Subsidiary Transfer

The main orchestration operation:

1. Create new identifier in target subsidiary
2. Promote new identifier to primary
3. Delete old identifier (complete transfer)

**Key Methods:**
- `4SKTrfNew(oUserIdResource)` - Constructor
- `4SKTrfExec(oSelf, cOldId, cOldSub, cNewId, cNewSub)` - Execute transfer
- `4SKTrfCont(oOrch)` - Continue from failure
- `4SKTrfRetry(oOrch)` - Retry from beginning

### 4.3 Tasks

- [ ] Implement base orchestration (4SKOrch.prw)
- [ ] Implement execution plan (4SKExecPl.prw)
- [ ] Implement orchestration step (4SKOrStep.prw)
- [ ] Implement user transfer (4SKUsrTrf.prw)
- [ ] Create orchestration tests

---

## Phase 5: Documentation

### 5.1 Documentation Structure

| File | Purpose |
|------|---------|
| README.md | Overview, installation, quick start |
| CHANGELOG.md | Version history |
| docs/INSTALLATION.md | Detailed installation for Protheus |
| docs/RESOURCES.md | API resources guide |
| docs/REFERENCE_VALUES.md | Value types and formats |
| docs/BEST_PRACTICES.md | Integration patterns |
| docs/USE_CASES.md | Practical examples |

### 5.2 Installation Guide Content

1. Prerequisites (Protheus 11+, TDS or VS Code)
2. Download/clone instructions from GitHub
3. Compilation steps (TDS or VS Code with TOTVS plugin)
4. Configuration (SX6 parameters or INI file)
5. Verification (health check example)

### 5.3 Tasks

- [ ] Write README.md
- [ ] Write INSTALLATION.md
- [ ] Migrate RESOURCES.md (adapt examples to AdvPL)
- [ ] Migrate REFERENCE_VALUES.md
- [ ] Migrate BEST_PRACTICES.md (adapt for AdvPL)
- [ ] Migrate USE_CASES.md (adapt examples)
- [ ] Create API reference documentation

---

## Phase 6: Examples

### 6.1 Example Programs

| File | Purpose |
|------|---------|
| BasicUsage.prw | Client initialization and health check |
| DealCreate.prw | Complete deal creation flow |
| UserTransfer.prw | User subsidiary transfer orchestration |

### 6.2 Tasks

- [ ] Create BasicUsage.prw example
- [ ] Create DealCreate.prw example
- [ ] Create UserTransfer.prw example
- [ ] Test all examples in Protheus environment

---

## Phase 7: Testing & Quality

### 7.1 Testing Strategy

Since AdvPL doesn't have a standard unit testing framework:

1. Create test functions in separate `.prw` files
2. Use `ConOut()` for test output
3. Manual testing in Protheus environment

### 7.2 Test Coverage

- [ ] Core components (client, options, request, response)
- [ ] All resource operations
- [ ] Orchestration flows
- [ ] Error handling scenarios
- [ ] Configuration validation

### 7.3 Tasks

- [ ] Create test harness
- [ ] Write core component tests
- [ ] Write resource tests
- [ ] Write orchestration tests
- [ ] Document testing procedure

---

## Phase 8: Distribution

### 8.1 Distribution Method

Since there's no "NuGet" for AdvPL:

1. **GitHub Repository** (primary)
   - Source files for compilation
   - Detailed installation guide

2. **Release Packages**
   - ZIP with all sources
   - Version-tagged releases

### 8.2 Tasks

- [ ] Create GitHub release workflow
- [ ] Write distribution documentation
- [ ] Create version tagging strategy
- [ ] Document update procedure for clients

---

## Success Criteria

1. All .NET SDK features available in AdvPL
2. Compatible with Protheus 11+
3. Complete documentation in English
4. Working examples for all major use cases
5. Clear installation and configuration guide (SX6 + INI)
6. Response parity with .NET SDK API calls

---

## Risks and Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| HTTP functions differ between Protheus versions | High | Use HttpGet/HttpPost (available since P11), test on multiple versions |
| JSON parsing variations | Medium | Use JsonObject if available, fallback to manual parser for older versions |
| No standard testing framework | Medium | Create simple test harness, document manual testing |
| 10-char function name limit | Low | Use abbreviation conventions, document mapping |
| HTTPS/TLS compatibility | Medium | Document SSL requirements, test certificate validation |

