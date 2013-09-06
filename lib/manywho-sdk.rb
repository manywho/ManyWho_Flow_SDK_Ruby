=begin

Copyright 2013 Manywho, Inc.

Licensed under the Manywho License, Version 1.0 (the "License"); you may not use this
file except in compliance with the License.

You may obtain a copy of the License at: http://manywho.com/sharedsource

Unless required by applicable law or agreed to in writing, software distributed under
the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
KIND, either express or implied. See the License for the specific language governing
permissions and limitations under the License.

=end

require "net/http"
require "net/https"
require "json"
require "date"
require "cgi"

HTTP = Net::HTTP.new("flow.manywho.com", 443)
HTTP.use_ssl = true

# OpenSSL verification
HTTP.verify_mode = OpenSSL::SSL::VERIFY_NONE

module ManyWho
	class Engine
        # Initialize instance variables
        def initialize
            reset()
        end
        
        def reset
            @TenantUID = false
            @LoginToken = false
        end
        
        # This method sets the Tenant Unique ID
		def set_tenant(tenantUniqueID)
            if ( is_valid_id(tenantUniqueID, "tenantUniqueId") )
                @TenantUID = tenantUniqueID
            end
		end
        
        # Tests if an id is valid, otherwise raises an error
        def is_valid_id(idString, idType)
            if (idString.is_a? String) && (idString =~ /^[-0-9a-f]+$/) &&
            (idString.length == 36) && (idString.count("-") == 4)
                return true
            else
                puts "Error: id is not valid (" + idType + "): " + idString.to_s
                return false
            end
        end
        
        # Tests if a request has completed successfully, otherwise raises an error
        def is_ok(resp, url)
            if (resp.code == "200") && (resp.body.length)
                return true
            else
                puts "Error: something went wrong in the rsponse (" + url +")"
                return false
            end
        end
        
        # Tests if a value is of a specified class type, otherwise raises an error
        def is_class(value, expectedClass, methodName, parameter)
            if (value.class.to_s == expectedClass.to_s)
                return true
            else
                puts "Error: parameter " + parameter.to_s + " of " + methodName + " must be a " + expectedClass.to_s + ". " +
                    "Parameter " + parameter.to_s + " was a " + value.class.to_s
                return false
            end
        end
        
        # Gets a FlowResponse object from the server for the provided ID
        def get_FlowResponse(flowId)
            if ( is_valid_id(flowId, "FlowId") )
                resp, data = HTTP.get("/api/run/1/flow/" + flowId,
                                    { "ManyWhoTenant" => @TenantUID , "content-type" => "application/json"} )
                # If everything went well, return a new FlowResponse from the JSON object retrieved
                if ( is_ok(resp, "/api/run/1/flow/" + flowId) )
                    parsedJSON = JSON.parse(resp.body)
                    return FlowResponse.new(parsedJSON)
                end
            end
            return false
        end
        
        # Creates an EngineInitializationRequest to be sent to the server using get_EngineInitializationResponse
        def create_EngineInitializationRequest(flowResponse, annotations = nil, inputs = [], mode = nil)
            # Ensure that all of the arguments are valid
            if ( is_class(flowResponse, FlowResponse, "create_EngineInitializationRequest", 1) ) &&
            ( (annotations == nil) or (is_class( annotations, Hash, "create_EngineInitializationRequest", "annotations")) ) &&
            ( (is_class( inputs, Array, "create_EngineInitializationRequest", "inputs")) ) &&
            ( (mode == nil) or (is_class( mode, String, "create_EngineInitializationRequest", "mode")) )
                # Create a hash to initialize the EngineInitializationRequest
                engineInitializationJSON = { "flowId" => flowResponse.id,
                                                "annotations" => annotations,
                                                "inputs" => inputs,
                                                "playerURL" => "https://flow.manywho.com/"+@TenantUID+"/play/myplayer",
                                                "joinPlayerURL" => "https://flow.manywho.com/"+@TenantUID+"/play/myplayer",
                                                "mode" => mode
                                            }
                return EngineInitializationRequest.new(engineInitializationJSON)
            end
            return false
        end
        
        # Gets an EngineInitializationResponse from the server, using a HTTP POST request.
        def get_EngineInitializationResponse(engineInitializationRequest)
            # Ensure that all of the arguments are valid
            if ( is_class(engineInitializationRequest, EngineInitializationRequest, "get_EngineInitializationResponse", 1) )
            
                # POST the EngineInitializationRequest
                resp, data = HTTP.post("/api/run/1/",
                                        engineInitializationRequest.to_json(),
                                        { "ManyWhoTenant" => @TenantUID , "content-type" => "application/json"} )
                
                # If everything went well, return a new EngineInitializationResponse created from the server's response
                if ( is_ok(resp, "/api/run/1/") )
                    parsedJSON = JSON.parse(resp.body)
                    return EngineInitializationResponse.new(parsedJSON)
                end
            end
            return false
        end
        
        # Logs in to the flow. Flows may require you to log in, this only has to be done once before executing the flow
        def login(engineInitializationResponse, username, password)
            # Ensure that all of the arguments are valid
            if ( is_class(engineInitializationResponse, EngineInitializationResponse, "login", 1) ) &&
            ( ( is_class(username, String, "login", 2) ) && (username.length) ) &&
            ( ( is_class(password, String, "login", 3) ) && (password.length) )
                
                # Create a logon request
                loginRequest = {
                    "loginUrl" => engineInitializationResponse.authorizationContext.loginUrl, #engineInitializationResponse.authorizationContext["loginUrl"],
                    "username" => username,
                    "password" => password
                }
                
                # POST the login request
                resp, data = HTTP.post("/api/run/1/authentication", 
                                        loginRequest.to_json(),
                                        { "ManyWhoTenant" => @TenantUID , "content-type" => "application/json"} )
                
                # If everything went well, set the logon token
                if ( is_ok(resp, "/api/run/1/authentication") )
                    @LoginToken = resp.body[1...resp.body.length-1]
                end
            end
            return false
        end
        
        # Create an EngineInvokeRequest to be posted to the server using get_EngineInvokeResponse
        def create_EngineInvokeRequest(engineInitializationResponse, flowResponse=nil, invokeType="FORWARD")
            # Ensure that all of the arguments are valid
            if ( is_class(engineInitializationResponse, EngineInitializationResponse, "create_EngineInvokeRequest", 1) ) &&
            ( is_class(invokeType, String, "create_EngineInvokeRequest", "invokeType") ) &&
            ( (flowResponse == nil) || (is_class(flowResponse, FlowResponse, "create_EngineInvokeRequest", "flowResponse")) )
                
                # If a flowResponse is provided, use the startMapElementId
                # If no flowResponse is provided, such as the engine is syncing, use the currentMapElementId
                if (flowResponse)
                    currentMapElementId = flowResponse.startMapElementId
                elsif 
                    currentMapElementId = engineInitializationResponse.currentMapElementId
                end
                
                # Create and return a new EngineInvokeRequest
                engineInvokeJSON = {
                                        "stateId" => engineInitializationResponse.stateId,
                                        "stateToken" => engineInitializationResponse.stateToken,
                                        "currentMapElementId" => currentMapElementId, #"7b2e4865-bd54-4073-b4f4-a4ec001afc9a", #### BODGE #### engineInitializationResponse.currentMapElementId,
                                        "invokeType" => invokeType,
                                        "geoLocation" => {
                                                            "latitude" => 0,
                                                            "longitude" => 0,
                                                            "accuracy" => 0,
                                                            "altitude" => 0,
                                                            "altitudeAccuracy" => 0,
                                                            "heading" => 0,
                                                            "speed" => 0
                                                        },
                                        "mapElementInvokeRequest" => {
                                                                        "selectedOutcomeId" => nil
                                                                    },
                                        "mode" => nil
                                    }
                return EngineInvokeRequest.new(engineInvokeJSON)
            end
            return false
        end
        
        # Create a EngineInvokeRequest from an engineInvokeResponse - such as when an outcome is selected, and a new EngineInvokeRequest is required
        def recreate_EngineInvokeRequest(engineInvokeResponse, selectedOutcomeId, invokeType="FORWARD")
            # Ensure that all of the arguments are valid
            if ( is_class(engineInvokeResponse, EngineInvokeResponse, "recreate_EngineInvokeRequest", 1) ) &&
            ( is_valid_id(selectedOutcomeId, "selectedOutcomeId") ) &&
            ( is_class(invokeType, String, "create_EngineInvokeRequest", "invokeType") )
                
                # Create and return a new EngineInvokeRequest
                engineInvokeJSON = {
                                        "stateId" => engineInvokeResponse.stateId,
                                        "stateToken" => engineInvokeResponse.stateToken,
                                        "currentMapElementId" => engineInvokeResponse.currentMapElementId,
                                        "invokeType" => invokeType,
                                        "geoLocation" => {
                                                            "latitude" => 0,
                                                            "longitude" => 0,
                                                            "accuracy" => 0,
                                                            "altitude" => 0,
                                                            "altitudeAccuracy" => 0,
                                                            "heading" => 0,
                                                            "speed" => 0
                                                        },
                                        "mapElementInvokeRequest" => {
                                                                        "selectedOutcomeId" => selectedOutcomeId
                                                                    },
                                        "mode" => nil
                                    }
                return EngineInvokeRequest.new(engineInvokeJSON)
            end
            return false
        end
        
        # Post the EngineInvokeRequest, and return the EngineInvokeResponse
        def get_EngineInvokeResponse(engineInvokeRequest)
            # Ensure that all arguments are valid
            if ( is_class(engineInvokeRequest, EngineInvokeRequest, "get_EngineInvokeResponse", 1) )
                if (@LoginToken)
                    # POST the EngineInvokeRequest, with authentication
                    resp, data = HTTP.post("/api/run/1/state/" + engineInvokeRequest.stateId,
                                            engineInvokeRequest.to_json,
                                            { "ManyWhoTenant" => @TenantUID , "content-type" => "application/json", "Authorization" => @LoginToken} )
                else
                    # POST the EngineInvokeRequest, without authentication
                    resp, data = HTTP.post("/api/run/1/state/" + engineInvokeRequest.stateId,
                                            engineInvokeRequest.to_json,
                                            { "ManyWhoTenant" => @TenantUID , "content-type" => "application/json"} )
                end
                
                # If everything went well, return a new EngineInvokeResponse created from the server's response
                if ( is_ok(resp, "/api/run/1/state/" + engineInvokeRequest.stateId) )
                    parsedJSON = JSON.parse(resp.body)
                    return EngineInvokeResponse.new(parsedJSON)
                end
            end
            return false
        end
        
        # Select an outcomeResponse, and get the next EngineInvokeResponse
        def select_OutcomeResponse(engineInvokeResponse, outcomeResponseDeveloperName, invokeType="FORWARD")
            # Ensure that all arguments are valid
            if ( is_class(engineInvokeResponse, EngineInvokeResponse, "select_OutcomeResponse", 1) ) &&
            ( is_class(outcomeResponseDeveloperName, String, "select_OutcomeResponse", 2) ) &&
            ( is_class(invokeType, String, "select_OutcomeResponse", "invokeType") )
                
                # Get the ID of the selected outcome, using the outcome's developerName
                selectedOutcomeId = nil
                engineInvokeResponse.mapElementInvokeResponses[0].outcomeResponses.each do |outcomeResp|
                    if (outcomeResp.developerName == outcomeResponseDeveloperName)
                        selectedOutcomeId = outcomeResp.id
                    end
                end

                # Create the EngineInvokeRequest from the EngineInvokeResponse
                engineInvokeRequest =  recreate_EngineInvokeRequest(engineInvokeResponse, selectedOutcomeId)
                
                # Return a new EngineInvokeResponse, created from data received from the server
                return get_EngineInvokeResponse( engineInvokeRequest )
            end
            return false
        end
        
        # Load a flow, given the tenantId, flowId and logon details the first EngineInvokeResponse will be returned
        def load_flow(tenant, flowId, username="", password="")
            # Ensure all the arguments are valid
            if ( is_valid_id(tenant, "tenantId") ) &&
            ( is_valid_id(flowId, "flowId") ) &&
            ( is_class(username, String, "load_flow", "username") ) &&
            ( is_class(password, String, "load_flow", "password") )
                # Set the tenant
                set_tenant(tenant)
                
                # Get the FlowResponse for the flow by id
                flowResponse = get_FlowResponse(flowId)
                
                # Create an EngineInitializationRequest, and use it to retreive an EngineInitializationResponse from the server
                engineInitializationResponse = get_EngineInitializationResponse(
                                                    create_EngineInitializationRequest( flowResponse )
                                                    )
                
                # If required to log in to the flow
                if (engineInitializationResponse.statusCode == "401")
                    # If login details, attempt to login
                    if (username != "") && (password != "")
                        login(engineInitializationResponse, username, password)
                    else
                        return "You need to login to run this flow: " + engineInitializationResponse.authorizationContext.loginUrl#["loginUrl"]
                    end
                end
                
                # Get a new EngineInvokeResponse from the server
                return engineInvokeResponse = get_EngineInvokeResponse(
                                                create_EngineInvokeRequest(engineInitializationResponse, flowResponse=flowResponse) )
            end
            return false
        end
    end
    
    # Initialized with a JSON hash, each value of the hash is converted into an instance variable. Can also be easily converted into a JSON string
    class MyStruct
        def to_json(options= {})
            hash = {}
            self.instance_variables.each do |var|
                hash[var[1...var.length]] = self.instance_variable_get var
            end
            return hash.to_json
        end
        
        # Set instance values from the hash
        def initialize(jsonValue)
            if (jsonValue != nil)
                jsonValue.each do
                    |k,v| self.instance_variable_set("@#{k}", v)
                end
            end
        end
    end
    
    class FlowResponse < MyStruct
        attr_accessor :dateCreated, :dateModified, :userCreated,
                        :userModified, :userOwner, :alertEmail,
                        :editingToken, :id, :developerName,
                        :developerSummary, :isActive, :startMapElementId,
                        :authorization
        
        def initialize(jsonValue)
            super(jsonValue)
            @id = FlowIdentifier.new(@id)
        end
    end
    
    class EngineInitializationRequest < MyStruct
        attr_accessor :flowId, :annotations, :inputs,
                        :mode
        
        def initialize(jsonValue)
            super(jsonValue)
            #@flowId = FlowIdentifier.new(@flowId)
            if (@inputs != nil)
                endArray = []
                @inputs.each do |input|
                    endArray += [EngineValue(input)]
                end
                @inputs = endArray
            end
            
        end
    end
    
    class EngineInitializationResponse < MyStruct
        attr_accessor :stateId, :stateToken, :currentMapElementId,
                        :currentMapElementId, :currentStreamId, :statusCode,
                        :authorizationContext
        def initialize(jsonValue)
            super(jsonValue)
            @authorizationContext = AuthorizationContext.new(@authorizationContext)
        end
    end
    
    class EngineInvokeRequest < MyStruct
        attr_accessor :stateId, :stateToken, :currentMapElementId,
                        :invokeType, :annotations, :geoLocatoin,
                        :mapElementInvokeRequest, :mode
        def initialize(jsonValue)
            super(jsonValue)
            @geoLocation = GeoLocation.new(@geoLocation)
            @mapElementInvokeRequest = MapElementInvokeResponse.new(@mapElementInvokeRequest)
        end
    end
    
    class MapElementInvokeRequest < MyStruct
        attr_accessor :selectedOutcomeId
    end
    
    class EngineInvokeResponse < MyStruct
        attr_accessor :stateId, :stateToken, :currentMapElementId,
                        :invokeType, :annotations, :mapElementInvokeResponses,
                        :stateLog, :preCommitStateValues, :stateValues,
                        :outputs, :statusCode, :runFlowUrl,
                        :joinFlowUrl, :authorizationContext
        def initialize(jsonValue)
            super(jsonValue)
            if (@mapElementInvokeResponses != nil)
                endArray = []
                @mapElementInvokeResponses.each do |invokeResponse|
                    endArray += [MapElementInvokeResponse.new(invokeResponse)]
                end
                @mapElementInvokeResponses = endArray
            end
            if (@preCommitStateValues != nil)
                endArray = []
                @preCommitStateValues.each do |preComitStateValue|
                    endArray += [EngineValue.new(preComitStateValue)]
                end
                @preCommitStateValues = endArray
            end
            if (@stateValues != nil)
                endArray = []
                @stateValues.each do |stateValue|
                    endArray += [EngineValue.new(stateValue)]
                end
                @stateValues = endArray
            end
            if (@outputs != nil)
                endArray = []
                @outputs.each do |output|
                    endArray += [EngineValue.new(output)]
                end
                @outputs = endArray
            end
            @authorizationContext = AuthorizationContext.new(@authorizationContext)
        end
    end

    class MapElementInvokeResponse < MyStruct
        attr_accessor :mapElementId, :developerName, :pageResponse,
                        :outcomeResponses, :rootFaults
        
        def initialize(jsonValue)
            super(jsonValue)
            @pageResponse = PageResponse.new(@pageResponse)
            if (@outcomeResponses != nil)
                endArray = []
                @outcomeResponses.each do |outputResponse|
                    endArray += [OutcomeResponse.new(outputResponse)]
                end
                @outcomeResponses = endArray
            end
        end
    end
    
    class PageResponse < MyStruct
        attr_accessor :label, :pageContainerResponses, :pageComponentResponses,
                        :pageContainerDataResponses, :pageComponentDataResponses, :order,
                        :outcomeResponses, :rootFaults
        def initialize(jsonValue)
            super(jsonValue)
            if (@pageContainerResponses != nil)
                endArray = []
                @pageContainerResponses.each do |pContainer|
                    endArray += [PageContainerResponse.new(pContainer)]
                end
                @pageContainerResponses = endArray
            end
            if (@pageComponentResponses != nil)
                endArray = []
                @pageComponentResponses.each do |pComponent|
                    endArray += [PageComponentResponse.new(pComponent)]
                end
                @pageComponentResponses = endArray
            end
            if (@pageContainerDataResponses != nil)
                endArray = []
                @pageContainerDataResponses.each do |pContainerData|
                    endArray += [PageContainerDataResponse.new(pContainerData)]
                end
                @pageContainerDataResponses = endArray
            end
            if (@pageComponentDataResponses != nil)
                endArray = []
                @pageComponentDataResponses.each do |pComponentData|
                    endArray += [PageComponentDataResponse.new(pComponentData)]
                end
                @pageComponentDataResponses = endArray
            end
            if (@outcomeResponses != nil)
                endArray = []
                @outcomeResponses.each do |outcomeResponse|
                    endArray += [OutcomeResponse.new(outcomeResponse)]
                end
                @outcomeResponses = endArray
            end
        end
    end
    
    class PageContainerResponse < MyStruct
        attr_accessor :id, :containerType, :developerName,
                        :label, :pageContainerResponses, :order
        def initialize(jsonValue)
            super(jsonValue)
            if (@pageContainerResponses != nil)
                endArray = []
                @pageContainerResponses.each do |pContainer|
                    endArray += [PageContainerResponse.new(pContainer)]
                end
                @pageContainerResponses = endArray
            end
        end
    end
    
    class PageComponentResponse < MyStruct
        attr_accessor :pageContainerDeveloperName, :pageContainerId, :id,
                        :developerName, :componentType, :contentType,
                        :label, :columns, :size,
                        :maxSize, :height, :width,
                        :hintValue, :helpInfo, :order,
                        :isMultiSelect, :hasEvents
    end
    
    class PageComponentDataResponse < MyStruct
        attr_accessor :pageComponentId, :isEnabled, :isEditable,
                        :isRequired, :isVisible, :objectData,
                        :objectDataRequest, :contentValue, :content,
                        :isValid, :validationMessage, :tags
    end
    
    class PageContainerDataResponse < MyStruct
        attr_accessor :pageContainerId, :isEnabled, :isVisible,
                        :tags
    end
    
    class OutcomeResponse < MyStruct
        attr_accessor :id, :developerName, :label,
                        :pageActionBinding, :formElementBindingId, :order
    end
    
    class GeoLocation < MyStruct
        attr_accessor :latitude, :longitude, :accuracy,
                        :altitude, :altitudeAccuracy, :heading,
                        :speed
    end
    
    class FlowIdentifier < MyStruct
        attr_accessor :id, :versionId
    end
    
    class AuthorizationContext < MyStruct
        attr_accessor :id, :directoryId, :loginUrl
    end
    
    class AuthorizationRequest < MyStruct
        attr_accessor :loginUrl, :username, :password,
                        :token
    end
    
    class EngineValue < MyStruct
        attr_accessor :id, :typeElementId, :typeElementEntryId,
                        :typeElementDeveloperName, :typeElementEntryDeveloperName, :contentValue,
                        :contentType, :id
    end
end