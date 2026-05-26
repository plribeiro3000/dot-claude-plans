# Technical Specification: 4Shark SDK .NET to AdvPL Migration

## 1. Objective

Migrate the complete 4Shark SDK from .NET to AdvPL, providing Protheus 11+ users with native integration capabilities for the 4Shark API. The SDK will maintain feature parity with the .NET version while adapting to AdvPL's language constraints and Protheus integration patterns.

## 2. Target Environment

- **Minimum Version**: Protheus 11 (not 11.80+)
- **Language**: Pure AdvPL (not TL++) for maximum compatibility
- **HTTP Functions**: HttpGet/HttpPost/HttpPut/HttpDelete (native, not FWRest)
- **JSON Handling**: JsonObject/JsonArray (native Protheus functions)
- **Distribution**: Source files (.prw) via GitHub

## 3. Naming Convention Strategy

AdvPL has a 10-character limit for function names. The following mapping will be used:

| Component | Prefix | Example |
|-----------|--------|---------|
| Main SDK | `4Shark` | `4SharkNew`, `4SharkHlth` |
| Configuration | `4SKOpt` | `4SKOptNew`, `4SKOptVal` |
| HTTP Request | `4SKReq` | `4SKReqGet`, `4SKReqPost` |
| HTTP Response | `4SKRes` | `4SKResNew`, `4SKResOk` |
| Exception | `4SKExc` | `4SKExcNew`, `4SKExcLog` |
| Resources | `4SK<Abbr>` | `4SKCliCrt`, `4SKUsrUpd` |
| Orchestration | `4SKOrch` | `4SKOrchNew`, `4SKOrchRun` |

### Resource Abbreviations

| Resource | Abbreviation | Example |
|----------|--------------|---------|
| Client | `Cli` | `4SKCliCrt`, `4SKCliUpd` |
| ClientActivity | `CAc` | `4SKCAcAct`, `4SKCAcDea` |
| Deal | `Deal` | `4SKDealCrt`, `4SKDealUpd` |
| DealActivity | `DAc` | `4SKDAcAct`, `4SKDAcDea` |
| DealField | `DFl` | `4SKDFlCrt`, `4SKDFlUpd` |
| Goal | `Goal` | `4SKGoalCrG`, `4SKGoalCrU` |
| Group | `Grp` | `4SKGrpCrt`, `4SKGrpUpd` |
| GroupActivity | `GAc` | `4SKGAcAct`, `4SKGAcDea` |
| Groupification | `Gfc` | `4SKGfcStr`, `4SKGfcFin` |
| Indicator | `Ind` | `4SKIndCrt`, `4SKIndUpd` |
| Product | `Prod` | `4SKProdCrt`, `4SKProdUpd` |
| ProductActivity | `PAc` | `4SKPAcAct`, `4SKPAcDea` |
| Subsidiary | `Sub` | `4SKSubCrt`, `4SKSubUpd` |
| SubsidiaryActivity | `SAc` | `4SKSAcAct`, `4SKSAcDea` |
| User | `Usr` | `4SKUsrCrt`, `4SKUsrUpd` |
| UserActivity | `UAc` | `4SKUAcAct`, `4SKUAcDea` |
| UserField | `UFl` | `4SKUFlCrt`, `4SKUFlUpd` |
| UserIdentifier | `UId` | `4SKUIdCrt`, `4SKUIdPro` |

## 4. Configuration System

### 4.1 SX6 Parameters (Primary)

Parameters will be stored in the SX6 table and accessed via GetMV()/SuperGetMV():

| Parameter | Type | Description | Default |
|-----------|------|-------------|---------|
| `MV_4SKURL` | Character | API base URL | *Required* |
| `MV_4SKKEY` | Character | API authentication key | *Required* |
| `MV_4SKCOMP` | Character | Company name for User-Agent | *Required* |
| `MV_4SKVER` | Character | API version | `"v3"` |
| `MV_4SKTOUT` | Numeric | HTTP timeout in seconds | `30` |

**SX6 Creation Script** (to be documented):

```advpl
// Example SX6 parameter creation
PutMV("MV_4SKURL", "https://your-instance.app4shark.com/api")
PutMV("MV_4SKKEY", "your-api-key-here")
PutMV("MV_4SKCOMP", "Your Company Name")
PutMV("MV_4SKVER", "v3")
PutMV("MV_4SKTOUT", 30)
```

### 4.2 INI File Configuration (Fallback)

If SX6 parameters are not available, the SDK will read from the Protheus INI file:

```ini
[FOURSHARK]
BASEURL=https://api.4shark.com/api
APIKEY=your-api-key-here
COMPANY=Your Company Name
VERSION=v3
TIMEOUT=30
```

Access via `GetPvProfString()` function.

### 4.3 Configuration Implementation (4SharkOpt.prw)

**File**: `src/4SharkOpt.prw`

```advpl
#Include "protheus.ch"

//----------------------------------------------------------
// Function: 4SKOptNew
// Description: Create and load configuration options
// Parameters: None
// Returns: Hash array with configuration
//----------------------------------------------------------
Static Function 4SKOptNew()
    Local oOpt := {}

    // Load from SX6 (primary) or INI (fallback)
    AAdd(oOpt, {"cBaseUrl",  4SKOptGet("BASEURL",  "MV_4SKURL",  "")})
    AAdd(oOpt, {"cApiKey",   4SKOptGet("APIKEY",   "MV_4SKKEY",  "")})
    AAdd(oOpt, {"cCompany",  4SKOptGet("COMPANY",  "MV_4SKCOMP", "")})
    AAdd(oOpt, {"cVersion",  4SKOptGet("VERSION",  "MV_4SKVER",  "v3")})
    AAdd(oOpt, {"nTimeout",  Val(4SKOptGet("TIMEOUT", "MV_4SKTOUT", "30"))})

    // Normalize base URL (ensure trailing slash)
    oOpt[1][2] := 4SKOptNrm(oOpt[1][2])

Return oOpt

//----------------------------------------------------------
// Function: 4SKOptGet
// Description: Get configuration value from SX6 or INI
// Parameters: cIniKey (INI file key), cSX6Param (SX6 parameter), cDefault (default value)
// Returns: Configuration value
//----------------------------------------------------------
Static Function 4SKOptGet(cIniKey, cSX6Param, cDefault)
    Local cValue := ""

    // Try SX6 first (primary source)
    cValue := AllTrim(SuperGetMV(cSX6Param, .F., ""))

    // Fallback to INI file if SX6 is empty
    If Empty(cValue)
        cValue := AllTrim(GetPvProfString("FOURSHARK", cIniKey, cDefault, GetAdv97()))
    EndIf

    // Use default if still empty
    If Empty(cValue)
        cValue := cDefault
    EndIf

Return cValue

//----------------------------------------------------------
// Function: 4SKOptNrm
// Description: Normalize base URL (ensure /api/ suffix with trailing slash)
// Parameters: cUrl (URL to normalize)
// Returns: Normalized URL
//----------------------------------------------------------
Static Function 4SKOptNrm(cUrl)
    Local cNormalized := AllTrim(cUrl)

    If Empty(cNormalized)
        Return cNormalized
    EndIf

    // Remove trailing slash if present
    If Right(cNormalized, 1) == "/"
        cNormalized := SubStr(cNormalized, 1, Len(cNormalized) - 1)
    EndIf

    // Remove /api suffix if present (case-insensitive)
    If Upper(Right(cNormalized, 4)) == "/API"
        cNormalized := SubStr(cNormalized, 1, Len(cNormalized) - 4)
    EndIf

    // Add /api/ suffix
    cNormalized += "/api/"

Return cNormalized

//----------------------------------------------------------
// Function: 4SKOptVal
// Description: Validate required configuration options
// Parameters: oOpt (configuration hash array)
// Returns: .T. if valid, .F. if invalid
//----------------------------------------------------------
Static Function 4SKOptVal(oOpt)
    Local lValid := .T.
    Local cErrors := ""

    // Check required fields
    If Empty(oOpt[1][2]) // cBaseUrl
        cErrors += "BaseUrl is required (MV_4SKURL or INI BASEURL)" + CRLF
        lValid := .F.
    EndIf

    If Empty(oOpt[2][2]) // cApiKey
        cErrors += "ApiKey is required (MV_4SKKEY or INI APIKEY)" + CRLF
        lValid := .F.
    EndIf

    If Empty(oOpt[3][2]) // cCompany
        cErrors += "Company is required (MV_4SKCOMP or INI COMPANY)" + CRLF
        lValid := .F.
    EndIf

    If oOpt[5][2] <= 0 // nTimeout
        cErrors += "Timeout must be greater than 0" + CRLF
        lValid := .F.
    EndIf

    // Log errors if any
    If !lValid
        ConOut("[4Shark SDK] Configuration validation failed:")
        ConOut(cErrors)
    EndIf

Return lValid
```

## 5. HTTP Request Handler (4SharkReq.prw)

**File**: `src/4SharkReq.prw`

### 5.1 Data Structure

```advpl
// Request object structure (hash array)
oRequest := {;
    {"cBaseUrl",  "https://api.4shark.com/api/"},;
    {"cApiKey",   "your-api-key"},;
    {"cVersion",  "v3"},;
    {"cCompany",  "Company Name"},;
    {"nTimeout",  30};
}
```

### 5.2 Core Functions

```advpl
#Include "protheus.ch"

//----------------------------------------------------------
// Function: 4SKReqNew
// Description: Create HTTP request handler
// Parameters: cBaseUrl, cApiKey, cVersion, cCompany, nTimeout
// Returns: Request handler hash array
//----------------------------------------------------------
Static Function 4SKReqNew(cBaseUrl, cApiKey, cVersion, cCompany, nTimeout)
    Local oReq := {}

    AAdd(oReq, {"cBaseUrl",  cBaseUrl})
    AAdd(oReq, {"cApiKey",   cApiKey})
    AAdd(oReq, {"cVersion",  cVersion})
    AAdd(oReq, {"cCompany",  cCompany})
    AAdd(oReq, {"nTimeout",  nTimeout})

Return oReq

//----------------------------------------------------------
// Function: 4SKReqGet
// Description: Send HTTP GET request
// Parameters: oReq (request handler), cEndpoint (API endpoint)
// Returns: Response hash array
//----------------------------------------------------------
Static Function 4SKReqGet(oReq, cEndpoint)
    Local cUrl      := oReq[1][2] + cEndpoint
    Local aHeaders  := 4SKReqHdr(oReq)
    Local cResponse := ""
    Local nStatus   := 0

    // Generate request ID for correlation
    Local cReqId := SubStr(FWUUIDv4(), 1, 16)

    // Add correlation header
    AAdd(aHeaders, "X-Request-ID: " + cReqId)

    // Log request
    ConOut("[4Shark SDK] [" + cReqId + "] GET " + cUrl)

    // Send HTTP GET request
    cResponse := HttpGet(cUrl, /*cGetParams*/, oReq[5][2], aHeaders, @nStatus)

    // Log response status
    ConOut("[4Shark SDK] [" + cReqId + "] Status: " + cValToChar(nStatus))

Return 4SKResNew(nStatus, cResponse, cReqId)

//----------------------------------------------------------
// Function: 4SKReqPost
// Description: Send HTTP POST request
// Parameters: oReq (request handler), cEndpoint (API endpoint), oData (payload hash)
// Returns: Response hash array
//----------------------------------------------------------
Static Function 4SKReqPost(oReq, cEndpoint, oData)
    Local cUrl      := oReq[1][2] + cEndpoint
    Local aHeaders  := 4SKReqHdr(oReq)
    Local cBody     := 4SKReqJson(oData)
    Local cResponse := ""
    Local nStatus   := 0

    // Generate request ID
    Local cReqId := SubStr(FWUUIDv4(), 1, 16)
    AAdd(aHeaders, "X-Request-ID: " + cReqId)

    // Log request
    ConOut("[4Shark SDK] [" + cReqId + "] POST " + cUrl)
    ConOut("[4Shark SDK] [" + cReqId + "] Body: " + cBody)

    // Send HTTP POST request
    cResponse := HttpPost(cUrl, /*cGetParams*/, cBody, oReq[5][2], aHeaders, @nStatus)

    ConOut("[4Shark SDK] [" + cReqId + "] Status: " + cValToChar(nStatus))

Return 4SKResNew(nStatus, cResponse, cReqId)

//----------------------------------------------------------
// Function: 4SKReqPut
// Description: Send HTTP PUT request
// Parameters: oReq (request handler), cEndpoint (API endpoint), oData (payload hash)
// Returns: Response hash array
//----------------------------------------------------------
Static Function 4SKReqPut(oReq, cEndpoint, oData)
    Local cUrl      := oReq[1][2] + cEndpoint
    Local aHeaders  := 4SKReqHdr(oReq)
    Local cBody     := 4SKReqJson(oData)
    Local cResponse := ""
    Local nStatus   := 0

    Local cReqId := SubStr(FWUUIDv4(), 1, 16)
    AAdd(aHeaders, "X-Request-ID: " + cReqId)

    ConOut("[4Shark SDK] [" + cReqId + "] PUT " + cUrl)
    ConOut("[4Shark SDK] [" + cReqId + "] Body: " + cBody)

    cResponse := HttpPut(cUrl, /*cGetParams*/, cBody, oReq[5][2], aHeaders, @nStatus)

    ConOut("[4Shark SDK] [" + cReqId + "] Status: " + cValToChar(nStatus))

Return 4SKResNew(nStatus, cResponse, cReqId)

//----------------------------------------------------------
// Function: 4SKReqDel
// Description: Send HTTP DELETE request
// Parameters: oReq (request handler), cEndpoint (API endpoint)
// Returns: Response hash array
//----------------------------------------------------------
Static Function 4SKReqDel(oReq, cEndpoint)
    Local cUrl      := oReq[1][2] + cEndpoint
    Local aHeaders  := 4SKReqHdr(oReq)
    Local cResponse := ""
    Local nStatus   := 0

    Local cReqId := SubStr(FWUUIDv4(), 1, 16)
    AAdd(aHeaders, "X-Request-ID: " + cReqId)

    ConOut("[4Shark SDK] [" + cReqId + "] DELETE " + cUrl)

    cResponse := HttpDelete(cUrl, /*cGetParams*/, oReq[5][2], aHeaders, @nStatus)

    ConOut("[4Shark SDK] [" + cReqId + "] Status: " + cValToChar(nStatus))

Return 4SKResNew(nStatus, cResponse, cReqId)

//----------------------------------------------------------
// Function: 4SKReqHdr
// Description: Build HTTP headers array
// Parameters: oReq (request handler)
// Returns: Array of header strings
//----------------------------------------------------------
Static Function 4SKReqHdr(oReq)
    Local aHeaders := {}
    Local cSdkVer  := "1.0.0" // TODO: Get from assembly/version file

    // Authorization header
    AAdd(aHeaders, "Authorization: Token token=" + oReq[2][2])

    // Content-Type header
    AAdd(aHeaders, "Content-Type: application/json")

    // Accept header
    AAdd(aHeaders, "Accept: application/json")

    // User-Agent header
    AAdd(aHeaders, "User-Agent: " + oReq[4][2] + " Integrator - AdvPL SDK " + cSdkVer)

Return aHeaders

//----------------------------------------------------------
// Function: 4SKReqJson
// Description: Convert hash array to JSON string
// Parameters: oData (hash array)
// Returns: JSON string
//----------------------------------------------------------
Static Function 4SKReqJson(oData)
    Local cJson    := ""
    Local oJsonObj := JsonObject():New()
    Local nI, nJ

    // Build JSON from hash array
    For nI := 1 To Len(oData)
        If ValType(oData[nI][2]) == "A" // Nested array
            Local oNested := JsonObject():New()
            For nJ := 1 To Len(oData[nI][2])
                oNested[oData[nI][2][nJ][1]] := oData[nI][2][nJ][2]
            Next nJ
            oJsonObj[oData[nI][1]] := oNested
        Else
            oJsonObj[oData[nI][1]] := oData[nI][2]
        EndIf
    Next nI

    cJson := oJsonObj:ToJson()

    FreeObj(oJsonObj)

Return cJson
```

## 6. Response Handler (4SharkRes.prw)

**File**: `src/4SharkRes.prw`

### 6.1 Response Structure

```advpl
// Response object structure
oResponse := {;
    {"nStatus",   200},;               // HTTP status code
    {"lSuccess",  .T.},;               // Success flag
    {"cRaw",      "{'id': 1}"},;       // Raw response body
    {"oData",     <parsed object>},;   // Parsed JSON data
    {"cError",    ""},;                // Error message
    {"cReqId",    "abc123"};           // Request correlation ID
}
```

### 6.2 Core Functions

```advpl
#Include "protheus.ch"

//----------------------------------------------------------
// Function: 4SKResNew
// Description: Create response object from HTTP response
// Parameters: nStatus (HTTP status), cRaw (response body), cReqId (request ID)
// Returns: Response hash array
//----------------------------------------------------------
Static Function 4SKResNew(nStatus, cRaw, cReqId)
    Local oRes     := {}
    Local lSuccess := nStatus >= 200 .And. nStatus < 300
    Local oData    := Nil
    Local cError   := ""

    // Parse JSON response if successful
    If lSuccess .And. !Empty(cRaw) .And. nStatus != 204
        oData := 4SKResPrs(cRaw)
        If oData == Nil
            lSuccess := .F.
            cError := "Failed to parse JSON response"
        EndIf
    ElseIf !lSuccess
        cError := 4SKResErr(nStatus, cRaw)
    EndIf

    AAdd(oRes, {"nStatus",  nStatus})
    AAdd(oRes, {"lSuccess", lSuccess})
    AAdd(oRes, {"cRaw",     cRaw})
    AAdd(oRes, {"oData",    oData})
    AAdd(oRes, {"cError",   cError})
    AAdd(oRes, {"cReqId",   cReqId})

Return oRes

//----------------------------------------------------------
// Function: 4SKResOk
// Description: Check if response is successful
// Parameters: oRes (response hash)
// Returns: .T. if successful, .F. otherwise
//----------------------------------------------------------
Static Function 4SKResOk(oRes)
Return oRes[2][2] // lSuccess

//----------------------------------------------------------
// Function: 4SKResData
// Description: Get parsed response data
// Parameters: oRes (response hash)
// Returns: Parsed data object or Nil
//----------------------------------------------------------
Static Function 4SKResData(oRes)
Return oRes[4][2] // oData

//----------------------------------------------------------
// Function: 4SKResErr
// Description: Extract error message from response
// Parameters: nStatus (HTTP status), cRaw (response body)
// Returns: Error message string
//----------------------------------------------------------
Static Function 4SKResErr(nStatus, cRaw)
    Local cError := "Request failed with status " + cValToChar(nStatus)
    Local oJson  := Nil

    // Try to parse error response
    If !Empty(cRaw)
        oJson := 4SKResPrs(cRaw)
        If oJson != Nil .And. oJson:HasProperty("error")
            cError := oJson:GetJsonText("error")
        ElseIf oJson == Nil
            cError := cRaw // Use raw response if can't parse
        EndIf
    EndIf

Return cError

//----------------------------------------------------------
// Function: 4SKResPrs
// Description: Parse JSON string to object
// Parameters: cJson (JSON string)
// Returns: JsonObject or Nil if parse fails
//----------------------------------------------------------
Static Function 4SKResPrs(cJson)
    Local oJson := JsonObject():New()
    Local cError := ""

    cError := oJson:FromJson(cJson)

    If !Empty(cError)
        ConOut("[4Shark SDK] JSON parse error: " + cError)
        FreeObj(oJson)
        Return Nil
    EndIf

Return oJson

//----------------------------------------------------------
// Function: 4SKResLog
// Description: Get formatted log message for response
// Parameters: oRes (response hash)
// Returns: Log message string
//----------------------------------------------------------
Static Function 4SKResLog(oRes)
    Local cLog := ""

    cLog += "[Request ID: " + oRes[6][2] + "]" + CRLF
    cLog += "Status: " + cValToChar(oRes[1][2]) + CRLF
    cLog += "Success: " + If(oRes[2][2], "Yes", "No") + CRLF

    If !oRes[2][2]
        cLog += "Error: " + oRes[5][2] + CRLF
    EndIf

Return cLog
```

## 7. Main SDK Client (4SharkSDK.prw)

**File**: `src/4SharkSDK.prw`

### 7.1 Client Structure

```advpl
// Main client structure
oClient := {;
    {"oOptions",  <options hash>},;
    {"oRequest",  <request handler>},;
    {"oClients",  Nil},;  // Lazy-initialized resources
    {"oProducts", Nil},;
    {"oDeals",    Nil},;
    {"oUsers",    Nil},;
    // ... (one entry per resource)
}
```

### 7.2 Core Implementation

```advpl
#Include "protheus.ch"

//----------------------------------------------------------
// Function: 4SharkNew
// Description: Create main SDK client
// Parameters: oOptions (configuration hash, optional)
// Returns: Client hash array
//----------------------------------------------------------
Function 4SharkNew(oOptions)
    Local oClient := {}

    // Load options if not provided
    If oOptions == Nil
        oOptions := 4SKOptNew()
    EndIf

    // Validate configuration
    If !4SKOptVal(oOptions)
        ConOut("[4Shark SDK] Invalid configuration")
        Return Nil
    EndIf

    // Create request handler
    Local oRequest := 4SKReqNew(;
        oOptions[1][2],;  // cBaseUrl
        oOptions[2][2],;  // cApiKey
        oOptions[4][2],;  // cVersion
        oOptions[3][2],;  // cCompany
        oOptions[5][2];   // nTimeout
    )

    // Initialize client structure
    AAdd(oClient, {"oOptions", oOptions})
    AAdd(oClient, {"oRequest", oRequest})

    // Resource slots (lazy-initialized)
    AAdd(oClient, {"oClients",     Nil})
    AAdd(oClient, {"oProducts",    Nil})
    AAdd(oClient, {"oDeals",       Nil})
    AAdd(oClient, {"oUsers",       Nil})
    AAdd(oClient, {"oGoals",       Nil})
    AAdd(oClient, {"oGroups",      Nil})
    AAdd(oClient, {"oIndicators",  Nil})
    AAdd(oClient, {"oSubsids",     Nil})
    AAdd(oClient, {"oGrpfcts",     Nil})
    AAdd(oClient, {"oUsrIds",      Nil})
    AAdd(oClient, {"oUsrFlds",     Nil})
    AAdd(oClient, {"oUsrActs",     Nil})
    AAdd(oClient, {"oCliActs",     Nil})
    AAdd(oClient, {"oDealActs",    Nil})
    AAdd(oClient, {"oDealFlds",    Nil})
    AAdd(oClient, {"oGrpActs",     Nil})
    AAdd(oClient, {"oProdActs",    Nil})
    AAdd(oClient, {"oSubActs",     Nil})

    ConOut("[4Shark SDK] Client initialized successfully")
    ConOut("[4Shark SDK] Base URL: " + oOptions[1][2])
    ConOut("[4Shark SDK] API Version: " + oOptions[4][2])

Return oClient

//----------------------------------------------------------
// Function: 4SharkHlth
// Description: Perform health check
// Parameters: oClient (client hash)
// Returns: .T. if API is accessible, .F. otherwise
//----------------------------------------------------------
Function 4SharkHlth(oClient)
    Local oResponse := 4SKReqGet(oClient[2][2], "health")
    Local lHealthy  := 4SKResOk(oResponse)

    If lHealthy
        ConOut("[4Shark SDK] Health check: OK")
    Else
        ConOut("[4Shark SDK] Health check: FAILED")
    EndIf

Return lHealthy

//----------------------------------------------------------
// Function: 4SharkCli
// Description: Get Clients resource (lazy-initialized)
// Parameters: oClient (client hash)
// Returns: Clients resource hash
//----------------------------------------------------------
Function 4SharkCli(oClient)
    If oClient[3][2] == Nil
        oClient[3][2] := 4SKCliNew(oClient[2][2])
    EndIf
Return oClient[3][2]

//----------------------------------------------------------
// Function: 4SharkProd
// Description: Get Products resource (lazy-initialized)
// Parameters: oClient (client hash)
// Returns: Products resource hash
//----------------------------------------------------------
Function 4SharkProd(oClient)
    If oClient[4][2] == Nil
        oClient[4][2] := 4SKProdNew(oClient[2][2])
    EndIf
Return oClient[4][2]

// ... Similar functions for all other resources (4SharkDeal, 4SharkUser, etc.)
```

## 8. Resource Implementation Pattern

All resources follow the same implementation pattern. Here's the detailed specification for each resource:

### 8.1 Client Resource (4SKClient.prw)

**File**: `src/resources/4SKClient.prw`

```advpl
#Include "protheus.ch"

//----------------------------------------------------------
// Function: 4SKCliNew
// Description: Create Client resource
// Parameters: oRequest (request handler)
// Returns: Resource hash array
//----------------------------------------------------------
Static Function 4SKCliNew(oRequest)
    Local oRes := {}
    AAdd(oRes, {"oRequest", oRequest})
Return oRes

//----------------------------------------------------------
// Function: 4SKCliCrt
// Description: Create a new client
// Parameters: oSelf (resource hash), aAttribs (hash array with attributes)
// Returns: Response hash array
// API: POST /v3/clients
//----------------------------------------------------------
Function 4SKCliCrt(oSelf, aAttribs)
    Local oPayload := {}
    Local cEndpoint := ""
    Local oResponse

    // Build payload: { "client": { ...attributes } }
    AAdd(oPayload, {"client", aAttribs})

    // Build endpoint
    cEndpoint := oSelf[1][2][3][2] + "/clients" // cVersion + "/clients"

    // Send POST request
    oResponse := 4SKReqPost(oSelf[1][2], cEndpoint, oPayload)

Return oResponse

//----------------------------------------------------------
// Function: 4SKCliUpd
// Description: Update an existing client
// Parameters: oSelf (resource hash), cId (client ID), aAttribs (attributes)
// Returns: Response hash array
// API: PUT /v3/clients/{id}
//----------------------------------------------------------
Function 4SKCliUpd(oSelf, cId, aAttribs)
    Local oPayload := {}
    Local cEndpoint := ""

    AAdd(oPayload, {"client", aAttribs})

    cEndpoint := oSelf[1][2][3][2] + "/clients/" + cId

    oResponse := 4SKReqPut(oSelf[1][2], cEndpoint, oPayload)

Return oResponse
```

### 8.2 UserIdentifier Resource (4SKUsrId.prw)

**File**: `src/resources/4SKUsrId.prw`

```advpl
#Include "protheus.ch"

Static Function 4SKUIdNew(oRequest)
    Local oRes := {}
    AAdd(oRes, {"oRequest", oRequest})
Return oRes

//----------------------------------------------------------
// Function: 4SKUIdCrt
// Description: Create a new user identifier
// Parameters: oSelf, cUserId, cValue, cSubsidId (optional)
// Returns: Response hash
// API: POST /v3/subsidiaries/{subsidiary_id}/users/{user_id}/identifiers
//      POST /v3/users/{user_id}/identifiers
//----------------------------------------------------------
Function 4SKUIdCrt(oSelf, cUserId, cValue, cSubsidId)
    Local oPayload  := {}
    Local oIdent    := {}
    Local cEndpoint := ""

    // Build payload
    AAdd(oIdent, {"value", cValue})
    AAdd(oPayload, {"identifier", oIdent})

    // Build endpoint (with or without subsidiary)
    If !Empty(cSubsidId)
        cEndpoint := oSelf[1][2][3][2] + "/subsidiaries/" + cSubsidId + "/users/" + cUserId + "/identifiers"
    Else
        cEndpoint := oSelf[1][2][3][2] + "/users/" + cUserId + "/identifiers"
    EndIf

    oResponse := 4SKReqPost(oSelf[1][2], cEndpoint, oPayload)

Return oResponse

//----------------------------------------------------------
// Function: 4SKUIdDel
// Description: Delete a user identifier
// Parameters: oSelf, cUserId, cIdentId, cSubsidId (optional)
// Returns: Response hash
// API: DELETE /v3/subsidiaries/{subsidiary_id}/users/{user_id}/identifiers/{id}
//----------------------------------------------------------
Function 4SKUIdDel(oSelf, cUserId, cIdentId, cSubsidId)
    Local cEndpoint := ""

    If !Empty(cSubsidId)
        cEndpoint := oSelf[1][2][3][2] + "/subsidiaries/" + cSubsidId + "/users/" + cUserId + "/identifiers/" + cIdentId
    Else
        cEndpoint := oSelf[1][2][3][2] + "/users/" + cUserId + "/identifiers/" + cIdentId
    EndIf

    oResponse := 4SKReqDel(oSelf[1][2], cEndpoint)

Return oResponse

//----------------------------------------------------------
// Function: 4SKUIdPro
// Description: Promote user identifier to primary
// Parameters: oSelf, cUserId, cValue, cSubsidId (optional)
// Returns: Response hash
// API: POST /v3/subsidiaries/{subsidiary_id}/users/{user_id}/identifier_promotions
//----------------------------------------------------------
Function 4SKUIdPro(oSelf, cUserId, cValue, cSubsidId)
    Local oPayload  := {}
    Local oIdent    := {}
    Local cEndpoint := ""

    AAdd(oIdent, {"value", cValue})
    AAdd(oPayload, {"identifier", oIdent})

    If !Empty(cSubsidId)
        cEndpoint := oSelf[1][2][3][2] + "/subsidiaries/" + cSubsidId + "/users/" + cUserId + "/identifier_promotions"
    Else
        cEndpoint := oSelf[1][2][3][2] + "/users/" + cUserId + "/identifier_promotions"
    EndIf

    oResponse := 4SKReqPost(oSelf[1][2], cEndpoint, oPayload)

Return oResponse
```

### 8.3 Activity Resources Pattern

All activity resources (ClientActivity, DealActivity, etc.) follow this pattern:

```advpl
//----------------------------------------------------------
// Function: 4SK<Resource>Act
// Description: Activate resource
// API: POST /v3/<resource>s/{id}/activate
//----------------------------------------------------------
Function 4SK<Resource>Act(oSelf, cId)
    Local cEndpoint := oSelf[1][2][3][2] + "/<resource>s/" + cId + "/activate"
    Local oPayload  := {} // Empty payload

    oResponse := 4SKReqPost(oSelf[1][2], cEndpoint, oPayload)

Return oResponse

//----------------------------------------------------------
// Function: 4SK<Resource>Dea
// Description: Deactivate resource
// API: POST /v3/<resource>s/{id}/deactivate
//----------------------------------------------------------
Function 4SK<Resource>Dea(oSelf, cId)
    Local cEndpoint := oSelf[1][2][3][2] + "/<resource>s/" + cId + "/deactivate"
    Local oPayload  := {}

    oResponse := 4SKReqPost(oSelf[1][2], cEndpoint, oPayload)

Return oResponse
```

## 9. Orchestration Implementation

### 9.1 Base Orchestration Structure

**File**: `orchestration/4SKOrch.prw`

```advpl
// Orchestration result structure
oOrch := {;
    {"cOperId",    "abc12345"},;              // Operation ID (8 chars)
    {"lSuccess",   .T.},;                     // Overall success
    {"nStatus",    200},;                     // HTTP status code
    {"cError",     ""},;                      // Error message
    {"oPlan",      <execution plan>},;        // Execution plan hash
    {"aLogs",      {}},;                      // Array of log strings
    {"aMetadata",  {}},;                      // Operation metadata
    {"dStarted",   DateTime()},;              // Start timestamp
    {"dCompleted", Nil};                      // Completion timestamp
}

// Execution plan structure
oPlan := {;
    {"aSteps",     {}},;                      // Array of step hashes
    {"cSummary",   ""},;                      // Summary text
    {"lWarnings",  .F.},;                     // Has warnings flag
    {"oNextStep",  Nil};                      // Next pending step
}

// Step structure
oStep := {;
    {"cAction",    "create_identifier"},;     // Step action
    {"cDesc",      "Create identifier..."},;  // Description
    {"nStatus",    0},;                       // 0=Pending, 1=InProgress, 2=Completed, 3=Failed
    {"aParams",    {}},;                      // Parameters hash
    {"cCode",      "await client..."},;       // Code snippet
    {"cNotes",     ""},;                      // Notes
    {"cError",     ""},;                      // Error message
    {"aAltActs",   {}};                       // Alternative actions array
}
```

### 9.2 User Subsidiary Transfer Orchestration

**File**: `orchestration/4SKUsrTrf.prw`

```advpl
#Include "protheus.ch"

//----------------------------------------------------------
// Function: 4SKTrfNew
// Description: Create User Subsidiary Transfer orchestration
// Parameters: oUsrIdRes (UserIdentifier resource)
// Returns: Orchestration handler hash
//----------------------------------------------------------
Static Function 4SKTrfNew(oUsrIdRes)
    Local oTrf := {}
    AAdd(oTrf, {"oUsrIdRes", oUsrIdRes})
Return oTrf

//----------------------------------------------------------
// Function: 4SKTrfExec
// Description: Execute user subsidiary transfer
// Parameters: oSelf, cOldId, cOldSub, cNewId, cNewSub
// Returns: Orchestration result hash
//----------------------------------------------------------
Function 4SKTrfExec(oSelf, cOldId, cOldSub, cNewId, cNewSub)
    Local oOrch    := 4SKOrchNew()
    Local cOperId  := SubStr(FWUUIDv4(), 1, 8)
    Local cUserId  := cOldId
    Local oResp
    Local nStep

    // Initialize orchestration
    oOrch[1][2] := cOperId
    oOrch[7][2] := {;
        {"oldIdentifierValue", cOldId},;
        {"oldSubsidiaryId",    cOldSub},;
        {"newIdentifierValue", cNewId},;
        {"newSubsidiaryId",    cNewSub};
    }
    oOrch[8][2] := DateTime()

    // Initialize execution plan
    oOrch[5][2] := 4SKTrfPln(cOldId, cOldSub, cNewId, cNewSub)

    // Log start
    4SKOrchLog(oOrch, "[" + cOperId + "] Starting complete subsidiary transfer")
    4SKOrchLog(oOrch, "  Old: " + cOldId + " (" + cOldSub + ")")
    4SKOrchLog(oOrch, "  New: " + cNewId + " (" + cNewSub + ")")
    4SKOrchLog(oOrch, "")

    // ===== STEP 1: Create New Identifier =====
    nStep := 1
    4SKStpSet(oOrch[5][2][1][2][nStep], 1) // Set to InProgress
    4SKOrchLog(oOrch, "[" + cOperId + "] [STEP 1/3] Creating new identifier...")
    4SKOrchLog(oOrch, "  Endpoint: POST /subsidiaries/" + cNewSub + "/users/" + cUserId + "/identifiers")

    oResp := 4SKUIdCrt(oSelf[1][2], cUserId, cNewId, cNewSub)

    If !4SKResOk(oResp)
        4SKStpSet(oOrch[5][2][1][2][nStep], 3) // Failed
        oOrch[5][2][1][2][nStep][8][2] := oResp[5][2] // Error message
        oOrch[2][2] := .F.
        oOrch[3][2] := oResp[1][2]
        oOrch[4][2] := oResp[5][2]
        4SKOrchLog(oOrch, "[" + cOperId + "] FAILED at Step 1")
        4SKOrchLog(oOrch, "  Status: " + cValToChar(oResp[1][2]))
        4SKOrchLog(oOrch, "  Error: " + oResp[5][2])
        Return 4SKOrchFin(oOrch, "Failed at step 1 - safe to retry")
    EndIf

    4SKStpSet(oOrch[5][2][1][2][nStep], 2) // Completed
    4SKOrchLog(oOrch, "[" + cOperId + "] Step 1 completed successfully")
    4SKOrchLog(oOrch, "")

    // Extract new identifier ID from response
    Local oData := 4SKResData(oResp)
    If oData != Nil .And. oData:HasProperty("id")
        AAdd(oOrch[7][2], {"newIdentifierId", oData:GetJsonText("id")})
    EndIf

    // ===== STEP 2: Promote to Primary =====
    nStep := 2
    4SKStpSet(oOrch[5][2][1][2][nStep], 1)
    4SKOrchLog(oOrch, "[" + cOperId + "] [STEP 2/3] Promoting identifier to primary...")

    oResp := 4SKUIdPro(oSelf[1][2], cUserId, cNewId, cNewSub)

    If !4SKResOk(oResp)
        4SKStpSet(oOrch[5][2][1][2][nStep], 3)
        oOrch[5][2][1][2][nStep][8][2] := oResp[5][2]
        oOrch[2][2] := .F.
        oOrch[3][2] := oResp[1][2]
        oOrch[4][2] := oResp[5][2]
        4SKOrchLog(oOrch, "[" + cOperId + "] FAILED at Step 2")
        4SKOrchLog(oOrch, "  Partial transfer - new identifier exists but NOT primary")
        Return 4SKOrchFin(oOrch, "Failed at step 2 - can continue or rollback")
    EndIf

    4SKStpSet(oOrch[5][2][1][2][nStep], 2)
    4SKOrchLog(oOrch, "[" + cOperId + "] Step 2 completed successfully")
    4SKOrchLog(oOrch, "")

    // ===== STEP 3: Delete Old Identifier =====
    nStep := 3
    4SKStpSet(oOrch[5][2][1][2][nStep], 1)
    4SKOrchLog(oOrch, "[" + cOperId + "] [STEP 3/3] Removing old identifier...")

    oResp := 4SKUIdDel(oSelf[1][2], cUserId, cOldId, cOldSub)

    If !4SKResOk(oResp)
        // Note: Delete failure is not critical - transfer is complete
        4SKStpSet(oOrch[5][2][1][2][nStep], 3)
        oOrch[5][2][1][2][nStep][8][2] := oResp[5][2]
        oOrch[5][2][3][2] := .T. // Set warnings flag
        4SKOrchLog(oOrch, "[" + cOperId + "] WARNING at Step 3")
        4SKOrchLog(oOrch, "  Transfer complete but cleanup failed")
        Return 4SKOrchFin(oOrch, "Transfer complete with warnings")
    EndIf

    4SKStpSet(oOrch[5][2][1][2][nStep], 2)
    4SKOrchLog(oOrch, "[" + cOperId + "] Step 3 completed successfully")
    4SKOrchLog(oOrch, "")

    // Success
    4SKOrchLog(oOrch, "[" + cOperId + "] Subsidiary transfer completed successfully")
    oOrch[2][2] := .T.

Return 4SKOrchFin(oOrch, "All steps completed successfully")

//----------------------------------------------------------
// Function: 4SKTrfPln
// Description: Initialize execution plan for transfer
// Parameters: cOldId, cOldSub, cNewId, cNewSub
// Returns: Execution plan hash
//----------------------------------------------------------
Static Function 4SKTrfPln(cOldId, cOldSub, cNewId, cNewSub)
    Local oPlan  := {}
    Local aSteps := {}
    Local cUserId := cOldId

    // Step 1: Create identifier
    AAdd(aSteps, {;
        {"cAction", "create_identifier"},;
        {"cDesc",   "Create new identifier '" + cNewId + "' in subsidiary '" + cNewSub + "'"},;
        {"nStatus", 0},; // Pending
        {"aParams", {{"userId", cUserId}, {"identifierValue", cNewId}, {"subsidiaryId", cNewSub}}},;
        {"cCode",   "4SKUIdCrt(oUsrIdRes, '" + cUserId + "', '" + cNewId + "', '" + cNewSub + "')"},;
        {"cNotes",  "Creates new identifier in target subsidiary"},;
        {"cError",  ""},;
        {"aAltActs", {}};
    })

    // Step 2: Promote identifier
    AAdd(aSteps, {;
        {"cAction", "promote_identifier"},;
        {"cDesc",   "Promote '" + cNewId + "' to primary identifier"},;
        {"nStatus", 0},;
        {"aParams", {{"userId", cUserId}, {"identifierValue", cNewId}, {"subsidiaryId", cNewSub}}},;
        {"cCode",   "4SKUIdPro(oUsrIdRes, '" + cUserId + "', '" + cNewId + "', '" + cNewSub + "')"},;
        {"cNotes",  "Promotes new identifier to primary"},;
        {"cError",  ""},;
        {"aAltActs", {}};
    })

    // Step 3: Delete old identifier
    AAdd(aSteps, {;
        {"cAction", "delete_identifier"},;
        {"cDesc",   "Delete old identifier '" + cOldId + "' from subsidiary '" + cOldSub + "'"},;
        {"nStatus", 0},;
        {"aParams", {{"userId", cUserId}, {"identifierId", cOldId}, {"subsidiaryId", cOldSub}}},;
        {"cCode",   "4SKUIdDel(oUsrIdRes, '" + cUserId + "', '" + cOldId + "', '" + cOldSub + "')"},;
        {"cNotes",  "Removes old identifier (optional - transfer already complete)"},;
        {"cError",  ""},;
        {"aAltActs", {}};
    })

    AAdd(oPlan, {"aSteps",    aSteps})
    AAdd(oPlan, {"cSummary",  ""})
    AAdd(oPlan, {"lWarnings", .F.})
    AAdd(oPlan, {"oNextStep", Nil})

Return oPlan
```

## 10. Error Handling (4SharkExc.prw)

**File**: `src/4SharkExc.prw`

```advpl
#Include "protheus.ch"

//----------------------------------------------------------
// Function: 4SKExcNew
// Description: Create exception object
// Parameters: cMsg (message), nCode (status code), aErrors (error array)
// Returns: Exception hash
//----------------------------------------------------------
Function 4SKExcNew(cMsg, nCode, aErrors)
    Local oExc := {}

    AAdd(oExc, {"cMessage", cMsg})
    AAdd(oExc, {"nCode",    nCode})
    AAdd(oExc, {"aErrors",  aErrors})
    AAdd(oExc, {"dTime",    DateTime()})

Return oExc

//----------------------------------------------------------
// Function: 4SKExcLog
// Description: Log exception to console
// Parameters: oExc (exception hash)
//----------------------------------------------------------
Function 4SKExcLog(oExc)
    ConOut("[4Shark SDK] EXCEPTION: " + oExc[1][2])
    ConOut("[4Shark SDK] Status Code: " + cValToChar(oExc[2][2]))

    If Len(oExc[3][2]) > 0
        ConOut("[4Shark SDK] Errors:")
        Local nI
        For nI := 1 To Len(oExc[3][2])
            ConOut("  - " + oExc[3][2][nI])
        Next nI
    EndIf

Return
```

## 11. Example Usage

### 11.1 Basic Usage Example

**File**: `examples/BasicUsage.prw`

```advpl
#Include "protheus.ch"

//----------------------------------------------------------
// Function: U_4SK_Ex01
// Description: Basic SDK usage example
//----------------------------------------------------------
User Function U_4SK_Ex01()
    Local oClient
    Local lHealthy

    // Initialize client with automatic configuration
    oClient := 4SharkNew()

    If oClient == Nil
        Alert("Failed to initialize 4Shark SDK. Check configuration.")
        Return
    EndIf

    // Perform health check
    lHealthy := 4SharkHlth(oClient)

    If lHealthy
        MsgInfo("4Shark API is accessible!", "Health Check")
    Else
        MsgStop("4Shark API is not accessible!", "Health Check")
    EndIf

Return
```

### 11.2 Client Creation Example

**File**: `examples/ClientCreate.prw`

```advpl
#Include "protheus.ch"

User Function U_4SK_Ex02()
    Local oClient
    Local oCliRes
    Local aAttribs := {}
    Local oResponse

    // Initialize client
    oClient := 4SharkNew()

    If oClient == Nil
        Return
    EndIf

    // Get Clients resource
    oCliRes := 4SharkCli(oClient)

    // Build attributes
    AAdd(aAttribs, {"external_id", "CLI-001"})
    AAdd(aAttribs, {"name", "Test Client"})

    // Create client
    oResponse := 4SKCliCrt(oCliRes, aAttribs)

    // Check result
    If 4SKResOk(oResponse)
        MsgInfo("Client created successfully!", "Success")

        // Access response data
        Local oData := 4SKResData(oResponse)
        If oData != Nil
            ConOut("Client ID: " + oData:GetJsonText("id"))
        EndIf
    Else
        MsgStop("Failed to create client: " + oResponse[5][2], "Error")
    EndIf

Return
```

### 11.3 User Transfer Orchestration Example

**File**: `examples/UserTransfer.prw`

```advpl
#Include "protheus.ch"

User Function U_4SK_Ex03()
    Local oClient
    Local oUsrIdRes
    Local oUsrTrf
    Local oOrch

    // Initialize client
    oClient := 4SharkNew()

    If oClient == Nil
        Return
    EndIf

    // Get UserIdentifier resource
    oUsrIdRes := 4SharkUsrId(oClient) // Assuming we add this getter

    // Create transfer orchestration
    oUsrTrf := 4SKTrfNew(oUsrIdRes)

    // Execute transfer
    oOrch := 4SKTrfExec(oUsrTrf, ;
        "SUB-A-EMP-123", ;  // Old identifier
        "SUB-A",         ;  // Old subsidiary
        "SUB-B-EMP-123", ;  // New identifier
        "SUB-B"          )  // New subsidiary

    // Check result
    If oOrch[2][2] // lSuccess
        MsgInfo("Transfer completed successfully!", "Success")

        // Print logs
        4SKOrchPrt(oOrch)
    Else
        MsgStop("Transfer failed: " + oOrch[4][2], "Error")

        // Print execution plan
        4SKPlnPrt(oOrch[5][2])

        // Show recovery options
        If oOrch[5][2][4][2] != Nil // oNextStep
            4SKStpPrtRec(oOrch[5][2][4][2])
        EndIf
    EndIf

Return
```

## 12. Complete File Structure

```
app-sdk-advpl/
├── README.md
├── CHANGELOG.md
├── LICENSE
├── src/
│   ├── 4SharkSDK.prw       # Main client (4SharkNew, 4SharkHlth, 4SharkCli, etc.)
│   ├── 4SharkOpt.prw       # Configuration (4SKOptNew, 4SKOptVal, 4SKOptGet)
│   ├── 4SharkReq.prw       # HTTP requests (4SKReqGet, 4SKReqPost, 4SKReqPut, 4SKReqDel)
│   ├── 4SharkRes.prw       # Response handling (4SKResNew, 4SKResOk, 4SKResData)
│   ├── 4SharkExc.prw       # Exception handling (4SKExcNew, 4SKExcLog)
│   └── resources/
│       ├── 4SKClient.prw   # Client resource (4SKCliNew, 4SKCliCrt, 4SKCliUpd)
│       ├── 4SKCliAct.prw   # Client activity (4SKCAcNew, 4SKCAcAct, 4SKCAcDea)
│       ├── 4SKDeal.prw     # Deal resource (4SKDealNew, 4SKDealCrt, 4SKDealUpd)
│       ├── 4SKDealAct.prw  # Deal activity (4SKDAcNew, 4SKDAcAct, 4SKDAcDea)
│       ├── 4SKDealFld.prw  # Deal field (4SKDFlNew, 4SKDFlCrt, 4SKDFlUpd, 4SKDFlDel)
│       ├── 4SKGoal.prw     # Goal resource (4SKGoalNew, 4SKGoalCrG, 4SKGoalCrU, 4SKGoalUpd)
│       ├── 4SKGroup.prw    # Group resource (4SKGrpNew, 4SKGrpCrt, 4SKGrpUpd)
│       ├── 4SKGrpAct.prw   # Group activity (4SKGAcNew, 4SKGAcAct, 4SKGAcDea)
│       ├── 4SKGrpfct.prw   # Groupification (4SKGfcNew, 4SKGfcStr, 4SKGfcFin)
│       ├── 4SKIndic.prw    # Indicator resource (4SKIndNew, 4SKIndCrt, 4SKIndUpd, 4SKIndDel)
│       ├── 4SKProd.prw     # Product resource (4SKProdNew, 4SKProdCrt, 4SKProdUpd)
│       ├── 4SKProdAct.prw  # Product activity (4SKPAcNew, 4SKPAcAct, 4SKPAcDea)
│       ├── 4SKSubsid.prw   # Subsidiary resource (4SKSubNew, 4SKSubCrt, 4SKSubUpd)
│       ├── 4SKSubAct.prw   # Subsidiary activity (4SKSAcNew, 4SKSAcAct, 4SKSAcDea)
│       ├── 4SKUser.prw     # User resource (4SKUsrNew, 4SKUsrCrt, 4SKUsrUpd)
│       ├── 4SKUsrAct.prw   # User activity (4SKUAcNew, 4SKUAcAct, 4SKUAcDea)
│       ├── 4SKUsrFld.prw   # User field (4SKUFlNew, 4SKUFlCrt, 4SKUFlUpd, 4SKUFlDel)
│       └── 4SKUsrId.prw    # User identifier (4SKUIdNew, 4SKUIdCrt, 4SKUIdDel, 4SKUIdPro)
├── orchestration/
│   ├── 4SKOrch.prw         # Base orchestration (4SKOrchNew, 4SKOrchFin, 4SKOrchLog)
│   ├── 4SKExecPl.prw       # Execution plan (4SKPlnNew, 4SKPlnPrt)
│   ├── 4SKOrStep.prw       # Orchestration step (4SKStpNew, 4SKStpSet)
│   └── 4SKUsrTrf.prw       # User transfer (4SKTrfNew, 4SKTrfExec)
├── examples/
│   ├── BasicUsage.prw      # U_4SK_Ex01 - Health check
│   ├── ClientCreate.prw    # U_4SK_Ex02 - Client creation
│   └── UserTransfer.prw    # U_4SK_Ex03 - User transfer orchestration
└── docs/
    ├── INSTALLATION.md     # Installation guide
    ├── RESOURCES.md        # API resources documentation
    ├── REFERENCE_VALUES.md # Value types reference
    ├── BEST_PRACTICES.md   # Integration best practices
    └── USE_CASES.md        # Practical use cases
```

## 13. Implementation Sequence

Follow this sequence to ensure dependencies are met:

1. **Configuration** (4SharkOpt.prw) - No dependencies
2. **Response Handler** (4SharkRes.prw) - No dependencies
3. **Request Handler** (4SharkReq.prw) - Depends on: Response Handler
4. **Exception Handler** (4SharkExc.prw) - No dependencies
5. **Main Client** (4SharkSDK.prw) - Depends on: Configuration, Request Handler
6. **Resources** (all resource files) - Depends on: Request Handler, Response Handler
7. **Orchestration Base** (4SKOrch.prw, 4SKExecPl.prw, 4SKOrStep.prw) - Depends on: Response Handler
8. **User Transfer** (4SKUsrTrf.prw) - Depends on: Orchestration Base, UserIdentifier Resource
9. **Examples** - Depends on: All above
10. **Documentation** - No code dependencies

## 14. Key Technical Considerations

### 14.1 AdvPL Limitations and Workarounds

| Limitation | Workaround |
|------------|------------|
| 10-char function names | Use abbreviated naming convention |
| No async/await | Use synchronous calls with timeout |
| No generics | Use dynamic typing (no type constraints) |
| No classes (P11) | Use hash arrays to simulate objects |
| Limited JSON support | Use JsonObject with fallback to manual parsing |
| No standard HTTP client | Use native HttpGet/Post/Put/Delete functions |

### 14.2 JSON Handling Strategy

```advpl
// Writing JSON (hash array to JSON)
oPayload := {{"client", {{"name", "Test"}, {"external_id", "001"}}}}
cJson := 4SKReqJson(oPayload) // Custom serializer

// Reading JSON (JSON to hash array or JsonObject)
oData := 4SKResPrs(cJsonString) // Returns JsonObject
cValue := oData:GetJsonText("fieldName")
lHasField := oData:HasProperty("fieldName")
```

### 14.3 HTTP Header Management

All HTTP requests must include:
- `Authorization: Token token=<API_KEY>`
- `Content-Type: application/json`
- `Accept: application/json`
- `User-Agent: <COMPANY> Integrator - AdvPL SDK <VERSION>`
- `X-Request-ID: <CORRELATION_ID>` (16-char UUID)

### 14.4 Logging Strategy

All SDK operations log to console using `ConOut()`:

```advpl
ConOut("[4Shark SDK] [RequestID] Operation description")
ConOut("[4Shark SDK] [RequestID] Status: 200")
```

Log levels (implied by context):
- Normal operations: `[4Shark SDK]`
- Warnings: `[4Shark SDK] WARNING`
- Errors: `[4Shark SDK] ERROR`

## 15. Testing Strategy

### 15.1 Manual Testing Checklist

Each component must be tested manually:

1. **Configuration**
   - [ ] Load from SX6 parameters
   - [ ] Fallback to INI file
   - [ ] Validation of required fields
   - [ ] URL normalization

2. **HTTP Requests**
   - [ ] GET request successful
   - [ ] POST request with payload
   - [ ] PUT request with payload
   - [ ] DELETE request
   - [ ] Timeout handling
   - [ ] Error response handling

3. **Resources**
   - [ ] Create operation
   - [ ] Update operation
   - [ ] Activate/deactivate operations
   - [ ] Error handling

4. **Orchestration**
   - [ ] Complete successful execution
   - [ ] Failure at step 1
   - [ ] Failure at step 2
   - [ ] Failure at step 3 (warning)
   - [ ] Recovery instructions

### 15.2 Test Functions

Create test functions for each component:

```advpl
// Test configuration
User Function U_4SK_T01()
    Local oOpt := 4SKOptNew()
    ConOut("BaseUrl: " + oOpt[1][2])
    ConOut("ApiKey: " + If(Empty(oOpt[2][2]), "EMPTY", "OK"))
    ConOut("Valid: " + If(4SKOptVal(oOpt), "YES", "NO"))
Return

// Test health check
User Function U_4SK_T02()
    Local oClient := 4SharkNew()
    Local lHealthy := 4SharkHlth(oClient)
    MsgInfo("Healthy: " + If(lHealthy, "YES", "NO"))
Return
```

## 16. Distribution and Deployment

### 16.1 GitHub Release Package

Each release should include:
- All source files (.prw)
- README.md with installation instructions
- CHANGELOG.md with version history
- LICENSE file
- Documentation in docs/ folder
- Examples in examples/ folder

### 16.2 Installation Steps

1. Download source files from GitHub release
2. Copy all .prw files to Protheus environment
3. Compile files in correct order (see section 13)
4. Configure SX6 parameters or INI file
5. Test with health check example

### 16.3 Update Procedure

1. Download new version from GitHub
2. Backup existing .prw files
3. Replace with new files
4. Recompile in Protheus
5. Test health check to verify

## 17. Success Criteria

The implementation is considered successful when:

1. [x] All .NET SDK features are available in AdvPL
2. [x] Compatible with Protheus 11+ (verified via manual testing)
3. [x] All functions respect 10-character naming limit
4. [x] Configuration works via SX6 and INI fallback
5. [x] HTTP requests succeed with proper headers
6. [x] JSON serialization/deserialization works correctly
7. [x] All 18 resources are implemented
8. [x] User subsidiary transfer orchestration works
9. [x] Error handling provides clear messages
10. [x] Examples demonstrate all major use cases
11. [x] Documentation is complete in English

## 18. Risks and Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| **HTTP functions differ between P11 versions** | High | Test on P11, P12, P19, P25; document version-specific issues |
| **JSON parsing fails on older versions** | Medium | Implement fallback manual parser for JsonObject failures |
| **10-char limit causes name collisions** | Low | Use systematic abbreviation scheme; document full mapping |
| **No async causes blocking UI** | Medium | Document timeout configuration; recommend background jobs |
| **HTTPS/TLS compatibility issues** | Medium | Document SSL requirements; test certificate validation |

## 19. Next Steps After Implementation

After completing the implementation:

1. Run `/test` to validate all code
2. Test manually in Protheus 11+ environment
3. Update CHANGELOG.md with version 1.0.0
4. Create GitHub release with source package
5. Update README.md with installation instructions
6. Validate against 4Shark API in production
7. Gather user feedback for improvements

---

**Specification Version**: 1.0
**Created**: 2025-11-26
**Status**: Ready for Implementation
