--- **Ops** - BarCAP Flightgroup
--
-- **Main Features:**
--
--    * Puts a Ops.FlightGroup#FLIGHTGROUP on a BarCap holding position, waiting to get an Intercept Ops.Auftrag#AUFTRAG assigned
--    * Takes a Airbase #string name as homebase of the Flightgroup
--    * Takes a Mission Editor defined late activated groupname #string as Flightgroup
--    * Takes Core.Point#COORDINATE for holding position
--    * Function to take Wrapper.Group#GROUP as target and assigns Intercept Auftrag
--    * To be used with Functional.Detection#DETECTION to assign targets
--    * Limitations - currently you can only have one barcap per mission
-- ===
--
-- ### Author: **applevangelist**
-- @module Ops.Barcap
--
--- BARCAP class.
-- @type BARCAP
-- @field #string Classname Name of the class.
-- @field #string name Name of the squadron.
-- @field #boolean verbose Display status messages.
-- @field #string lid Class id string for output to DCS log file.
-- @field #string template Name of the late activated group to use from Mission Editor
-- @field #string homebase Homebase airbase of the BarCap operation
-- @field #number flightno (internal) counter
-- @field Core.Point#COORDINATE Capcoord The holding position for BarCap
-- @field #number ammothreshold How many AA missiles need to be left in the group when deciding to assign the next Ops.Auftrag#AUFTRAG 
-- @field #boolean debug Debug state, switch reports on/off
-- @extends Core.Fsm#FSM

--- *The worst thing that can happen to a good cause is, not to be skillfully attacked, but to be ineptly defended.* - Frédéric Bastiat 
-- 
-- Simple FSM for BARCAP with AUFTRAG
-- 
-- #BARCAP
-- Barrier Air Combat Patrol.
-- One or more divisions or elements of fighter aircraft employed between a force and an objective area as a barrier across the probable direction of enemy attack. 
-- It is used as far from the force as control conditions permit, giving added protection against raids that use the most direct routes of approach.
--
-- @field #BARCAP
BARCAP = {
  ClassName         = "BARCAP",
  name              =  "generic",  --#string
  verbose           =  false, --#boolean
  lid               =  "", --#string
  template          = "", --#string
  homebase           = "", --#string
  flightno          = 0,  --#number
  Capcoord          =  {}, --Core.Positionable#COORDINATE Object 
  ammothreshold     =  4,   --#number
  debug             = false,  --#boolean
}

-- @field #string version
BARCAP.version="0.3.0"
env.info(string.format("***** Starting BARCAP Version %s *****", BARCAP.version))

-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- TODO list
-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

-- TODO: make multiple object safe (how to get around usage of globals?)
-- TODO: loads of other stuff

-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Constructor
-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

--- Create a new BARCAP object and start the FSM.
-- @param #BARCAP self
-- @return #BARCAP self
function BARCAP:New()

  -- set initial parameters
  -- internal globals
  _BARCAP_GRUPPE = nil --Wrapper.Group#GROUP current active Group object
  _BARCAP_AUFTRAG = nil --Ops.Auftrag#AUFTRAG current active Auftrag object
  _BARCAP_ROTTE = nil --Ops.FlightGroup#FLIGHTGROUP current active Flightgroup object
  _BARCAP_GRPNAME = nil --#string Name of the _BARCAP_GRUPPE 
  _BARCAP_STATE = nil --#string Global state
  
  -- Inherit everything from FSM class.
  local self=BASE:Inherit(self, FSM:New()) -- #BARCAP

  -- Set some string id for output to DCS.log file.
  self.lid=string.format("BARCAP %s | ", self.name)
  
  --set start state
  self:SetStartState("Off")

  -- transitions
  -- From -- Event -- To
  self:AddTransition( "Off", "Start", "Initializing" )
  self:AddTransition( {"Initializing", "Executing", "Intercepting"}, "Execute", "Executing")
  self:AddTransition( "Executing", "Intercept", "Intercepting")
  self:AddTransition("Initializing", "Prep", "Initializing")
  self:AddTransition( "Executing", "ReInit", "Initializing" )
  self:AddTransition( "*", "Stop", "Off" )
  self:AddTransition( "*", "Status", "*" )

  ------------------------
  --- Pseudo Functions ---
  ------------------------

  --- Triggers the FSM event "Start". Starts the BARCAP. Initializes parameters and starts event handlers.
  -- @function [parent=#BARCAP] Start
  -- @param #BARCAP self

  --- Triggers the FSM event "Start" after0 a delay. Starts the BARCAP. Initializes parameters and starts event handlers.
  -- @function [parent=#BARCAP] __Start
  -- @param #BARCAP self
  -- @param #number delay Delay in seconds.

  --- Triggers the FSM event "Stop". Stops the BARCAP and all its event handlers.
  -- @param #BARCAP self

  --- Triggers the FSM event "Stop" after a delay. Stops the BARCAP and all its event handlers.
  -- @function [parent=#BARCAP] __Stop
  -- @param #BARCAP self
  -- @param #number delay Delay in seconds.

  --- Triggers the FSM event "Status".
  -- @function [parent=#BARCAP] Status
  -- @param #BARCAP self

  --- Triggers the FSM event "Status" after a delay.
  -- @function [parent=#BARCAP] __Status
  -- @param #BARCAP self
  -- @param #number delay Delay in seconds.


  -- Debug trace.
  if self.debug then
    BASE:TraceOnOff(true)
    BASE:TraceClass(self.ClassName)
    BASE:TraceClass("AUFTRAG")
    BASE:TraceClass("FLIGHTGROUP")
    BASE:TraceLevel(1)
  end

  return self
  
end

-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Helper Functions
-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

--- Set target group for Intercept Auftrag
-- @param #BARCAP self
-- @param Wrapper.Group#GROUP tgtgroup Target group object
function BARCAP:AttackTarget(tgtgroup)
  -- check is group is alive
  if tgtgroup ~= nil then
    if tgtgroup:IsAlive() then
    --yes, we can
    self.Target = tgtgroup
    self:__Intercept(-5)
    end
  end  
end

--- Set display name of the BarCap operation
-- @param #BARCAP self
-- @param #string name Name to display
function BARCAP:SetName(name) -- needs to be a #string
  self.name = name
end

--- Set home airbase of the BarCap operation
-- @param #BARCAP self
-- @param #string airbase Airbase to use 
function BARCAP:SetHomebase(airbase) -- needs to be a #string
  self.homebase = airbase
end

--- Set template name of the planes to use
-- @param #BARCAP self
-- @param #string tempname Name of the ME late activated group to be used as template
function BARCAP:SetTemplate(tempname) -- needs to be a #string
  self.template = tempname
end

--- Set BarCap holding coordinate
-- @param #BARCAP self
-- @param Core.Point#COORDINATE capzone Coordinate of the holding position
function BARCAP:SetCapCoord(capzone) -- needs to be a #Coordinate Object
  self.Capcoord = capzone
end

--- Set threshold for AA missiles to be left on group
-- @param #BARCAP self
-- @param #number number Minimum amount of missiles to be left over
function BARCAP:SetAmmoTreshold(number) -- needs to be a #number
  self.ammothreshold = number
end

--- Allow status reports
-- @param #BARCAP self
-- @param #boolean value Set BarCap FSM reports on
function BARCAP:SetVerbose(value) -- needs to be a #boolean
  self.verbose = value
end

--- Spawn new group
-- @param #BARCAP self
-- @param #number number Current flight number
-- @return #string flightname Alias of the spawned group
function BARCAP:NewSpawnGroup(number)
  -- spawn new group
  local base = self.homebase
  local homebase = AIRBASE:FindByName(base)
  local templ = self.template
  local flightname = string.format("%s-BCAP-%d", templ, number)
  _BARCAP_GRPNAME = flightname
  local group = SPAWN:NewWithAlias(templ,flightname)
  group:InitAirbase(homebase,SPAWN.Takeoff.Hot)
  group:InitDelayOff()
  --group:InitLimit(4,4)
  group:OnSpawnGroup(
    function (spwngrp)
      _BARCAP_GRUPPE = spwngrp
    end
  )
  group:SpawnScheduled(30,0)
  return flightname
end

--- Create new BarCap Auftrag
-- @param #BARCAP self
-- @return Ops.Auftrag#AUFTRAG capauftrag Returns Auftrag object
function BARCAP:NewCAPAuftrag()
  -- create new Aufttrag
  capauftrag = AUFTRAG
        :NewGCICAP(self.Capcoord,15000,300,0,10)
        :SetMissionRange(200)
        :SetPriority(20,false,10)
        :SetVerbosity(1)
        :SetRequiredAssets(2)
        --:SetTime(5,600)
  function capauftrag:OnAfterFailed(From,Event,To)
    _BARCAP_STATE = "Failed"
  end
  --     
  return capauftrag
end  

--- Create new intercept Auftrag
-- @param #BARCAP self
-- @param Wrapper.Group#GROUP ziel Target group object
-- @return Ops.Auftrag#AUFTRAG intauftrag Returns Auftrag object
function BARCAP:NewINTAuftrag(ziel)
  -- create new Aufttrag
  intauftrag = AUFTRAG
        :NewINTERCEPT(ziel)
        :SetMissionRange(200)
        :SetMissionSpeed("1000")
        :SetPriority(10,true,10)
        :SetVerbosity(1)
        :SetRequiredAssets(2)
        --:SetTime(5,600)
  function intauftrag:OnAfterFailed(From,Event,To)
    _BARCAP_STATE = "Failed"
  end
  
  function intauftrag:OnAfterSuccess(From,Event,To)
    _BARCAP_STATE = "Success"
  end
  --     
  return intauftrag
end 

--- Create new Flightgroup
-- @param #BARCAP self
-- @param Wrapper.Group#GROUP gruppe Base Group object to be used
-- @return Ops.FlightGroup#FLIGHTGROUP flight Returns Flightgroup object
function BARCAP:NewFlightGroup(gruppe)
  local flight = nil
  local homebase = AIRBASE:FindByName(self.homebase)
  -- Short info.
  local text=string.format("BARCAP | Get Flight Group")
  self:F(text)  
  m = MESSAGE:New(text,15,"Info"):ToAllIf(self.verbose)
  --
 flight = FLIGHTGROUP:New(gruppe)
    flight:New(gruppe)
    flight:SetHomebase(homebase)
    flight:SetDespawnAfterLanding()
    flight:SetDefaultRadio(300,"AM",false)
    flight:SetFuelCriticalRTB(true)
    flight:SetVerbosity(0)
    --flight:Activate()
  return flight
end

--- Check if Flightgroup is ready for (next) Auftrag
-- @param #BARCAP self
-- @param Ops.FlightGroup#FLIGHTGROUP wing Current Flightgroup to check
-- @return #boolean ready Returns boolean ready state
function BARCAP:CheckFlightReady(wing)
  local air = "no"
  local fuel = "no"
  local rotte = wing --Ops.FlightGrooup#FLIGHTGROUP
  local ammolim = self.ammothreshold
  local ready = false
  local ammotable = rotte:GetAmmoTot()
  local missiles = ammotable.MissilesAA
  if (rotte:IsAirborne() or rotte:IsInbound()) and (missiles > ammolim) then
    if rotte:IsFuelLow() then
      ready = false
    else
      ready = true
    end
  end
  if (rotte:IsAirborne() or rotte:IsInbound()) then
    air = "yes"
  end
  if rotte:IsFuelLow() then
    fuel = "yes"
  end
  -- Short info.
  local text=string.format("BARCAP | Flight State: Airborne: %s Low Fuel: %s Missiles: %d (%d)", air, fuel, missiles, ammolim)
  self:F(text)  
  m = MESSAGE:New(text,15,"Info"):ToAllIf(self.verbose)
  return ready 
end

-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Start
-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

--- On after Start event. Checks parameters and starts execution
-- @param #BARCAP self
-- @param #string From From state.
-- @param #string Event Event.
-- @param #string To To state.
function BARCAP:onafterStart(From, Event, To)
  self:F( { From, Event, To })
  -- Set some string id for output to DCS.log file.
  self.lid=string.format("BARCAP %s | ", self.name)
  -- Short info.
  local text=string.format("Starting BARCAP", self.name)
  self:F(self.lid..text)  
  m = MESSAGE:New(self.lid..text,15,"Info"):ToAllIf(self.verbose)
  -- check if we are ready to go
  if self.homebase == "" or self.template == "" or self.Capcoord == nil then
    m = MESSAGE:New("Please set Homebase, Template and Coordinate first!",15,"Info"):ToAllIf(self.verbose)
    self:Stop()
  else
    _BARCAP_STATE = "Starting"
    self:__Prep(10)
  end
end

--- On enter Initializing state. Preps & checks Group, Auftrag and Flightgroup state if ready to go.
-- @param #BARCAP self
-- @param #string From From state.
-- @param #string Event Event.
-- @param #string To To state
function BARCAP:onenterInitializing(From,Event,To)
  self:F( { From, Event, To })
  -- Short info.
  local text=string.format("Init BARCAP", self.name)
  self:F(self.lid..text)
  m = MESSAGE:New(self.lid..text,15,"Info"):ToAllIf(self.verbose)
  --
  local gruppe = _BARCAP_GRUPPE
  local gruppealive = false
  if gruppe == nil then
    gruppealive = false
  else
    gruppealive = true
    --test it
    getgroup = GROUP:FindByName(_BARCAP_GRPNAME)
  end
  --
  local rotte = _BARCAP_ROTTE
  local rottealive = false
  if rotte == nil then
    rottealive = false
  else
    rottealive = true
    --test it
    getgroup = _BARCAP_ROTTE:GetState()
  end
  --
  if From == "Off" or From == "Executing" then
    self.flightno = self.flightno+1
    local nummer = self.flightno
    _BARCAP_GRPNAME = self:NewSpawnGroup(nummer)
    _BARCAP_AUFTRAG = self:NewCAPAuftrag()
    self:__Prep(10)
  else -- from ~= Off
      if From == "Initializing" then
        -- lets see where we are
        local aufgabe = _BARCAP_AUFTRAG
        -- AUFTRAG *might* be over already
        if aufgabe:IsOver() then 
          -- we need a new Auftrag
          _BARCAP_AUFTRAG = self:NewCAPAuftrag()
        end
        -- get some status
        if gruppealive and aufgabe:IsNotOver() and rotte == nil then
          -- get us a flightgrp pls
          _BARCAP_ROTTE = self:NewFlightGroup(gruppe)
          self:__Prep(10)        
        end
        if gruppealive and aufgabe:IsNotOver() and rottealive then
            _BARCAP_STATE = "Executing"
            self:__Execute(-15)
        end -- group task and flight alive
      end -- group and task alive  
  end --if Off
  self:__Prep(10)
end --function

--- On after Execute event. Starts the mission for a Flightgroup
-- @param #BARCAP self
-- @param #string From From state.
-- @param #string Event Event.
-- @param #string To To state.
function BARCAP:onafterExecute(From, Event, To)
  self:F( { From, Event, To })
  -- Short info.
  local text=string.format("Executing BARCAP")
  self:F(self.lid..text)  
  m = MESSAGE:New(self.lid..text,15,"Info"):ToAllIf(self.verbose)
  -- Get Going
  if From == "Initializing" or From == "Intercepting" then 
    --asume all ready to go
    _BARCAP_ROTTE:AddMission(_BARCAP_AUFTRAG)
  end
  self:__Status(-60)
end

--- On after Intercept event. Creates Intercept Auftrag for Target
-- @param #BARCAP self
-- @param #string From From state.
-- @param #string Event Event.
-- @param #string To To state.
function BARCAP:onafterIntercept(From,Event,To)
  self:F( { From, Event, To })
  -- Short info.
  local target = self.Target
  local targetname = target:GetName()
  local text=string.format("BARCAP: Intercept target %s", targetname)
  self:F(self.lid..text)  
  m = MESSAGE:New(self.lid..text,15,"Info"):ToAllIf(self.verbose)
  -- Get Going
  local rotte = _BARCAP_ROTTE
  iAuftrag = self:NewINTAuftrag(target)
  --
  _BARCAP_AUFTRAG = iAuftrag
  _BARCAP_STATE = "Intercepting"
  self:__Execute(-5)
end
-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Status
-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

--- On before Status event. Checks global state.
-- @param #BARCAP self
-- @param #string From From state.
-- @param #string Event Event.
-- @param #string To To state.
function BARCAP:onbeforeStatus(From, Event, To)
  self:F( { From, Event, To })
  local state = _BARCAP_STATE
  local text=string.format("Global State: %s ", state)
  self:F(self.lid..text)  
  m = MESSAGE:New(self.lid..text,15,"Info"):ToAllIf(self.verbose)
end

--- On after Status event. Creates status report. Checks on mission and group status. Assigns new BarCap task.
-- @param #BARCAP self
-- @param #string From From state.
-- @param #string Event Event.
-- @param #string To To state.
function BARCAP:onafterStatus(From, Event, To)
  self:F( { From, Event, To })
  -- Get some updates
  local grpname = "none"
  if _BARCAP_STATE ~= "Failed" then --we're still alive
    if _BARCAP_GRUPPE ~= nil then
      if _BARCAP_GRUPPE:IsAlive() then
        grpname = _BARCAP_GRUPPE:GetName()
      end
    end
    local Astate =  _BARCAP_AUFTRAG:GetState()
    local AType =  _BARCAP_AUFTRAG:GetType()
    local Rstate = _BARCAP_ROTTE:GetState()
    local Fname = _BARCAP_GRPNAME
    -- Short info.
    local text=string.format("Status: %s (%s) executing in state %s with Auftrag %s state %s", grpname, Fname, Rstate, AType, Astate)
    self:F(self.lid..text)  
    m = MESSAGE:New(self.lid..text,15,"Info"):ToAllIf(self.verbose)
    --
    if Rstate == "Inbound" then
      -- Auftrag done, we need a new one
      --DONE take decisions on state below
      --DONE check if we're low fuel and/or out of ammo
      local rotte = _BARCAP_ROTTE
      local isready = self:CheckFlightReady(rotte)
      --
      if isready then
        -- can assign new Auftrag
        cAuftrag = self:NewCAPAuftrag()
        _BARCAP_AUFTRAG = cAuftrag
        _BARCAP_ROTTE:__Airborne(-5) -- keep it going
        _BARCAP_ROTTE:AddMission(cAuftrag)
        _BARCAP_STATE ="Executing"
      else
        -- need a new group
        _BARCAP_STATE ="Failed"
        _BARCAP_AUFTRAG:Cancel()
      end
    end
    self:__Status(-60)
  else
    -- we're dead
    _BARCAP_GRUPPE = nil
    _BARCAP_AUFTRAG = nil
    _BARCAP_ROTTE = nil
    _BARCAP_GRPNAME = nil
    self:__ReInit(-5)
  end
end

-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Stop
-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

--- On after Stop event. Stops the mission for an AIRWING
-- @param #BARCAP self
-- @param #string From From state.
-- @param #string Event Event.
-- @param #string To To state.
function BARCAP:onafterStop(From, Event, To)
  self:F( { From, Event, To })
  text = "BARCAP state:"..self:GetState()
  m = MESSAGE:New(text,15,"Info"):ToAllIf(self.verbose)
  --TODO: maybe cleanup ongoing Auftrag if any?
  _BARCAP_AUFTRAG:Cancel() --not sure if necessary
end

-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- The End
-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

-- EXAMPLE
-- start a new BARCAP object
-- get a holding position coordinate
local capcoordinate = ZONE:New("Zone-1"):GetCoordinate()
-- create object
mybarcap = BARCAP:New()
-- set name for display
mybarcap:SetName("AdA Alsace")
--mybarcap:SetName("492 Sq")
-- set homebase - needs to be a real airbase name on the map!
mybarcap:SetHomebase("Mozdok")
-- set template group to use
--mybarcap:SetTemplate("AdA Alsace")
mybarcap:SetTemplate("492 Sq")
-- set coordinates
mybarcap:SetCapCoord(capcoordinate)
-- set AA missiles threshold
mybarcap:SetAmmoTreshold(6)
-- set reports on/off
mybarcap:SetVerbose(true)
-- get going
mybarcap:Start()

-- get us some enemies
function redinterceptors()
  -- spawn new enemies for current group
  redm29s = SPAWN
    :New("RedPatMig29HH")
    :InitDelayOff()
    :OnSpawnGroup(
    function(migs)
      -- assign to attack this flight
      mybarcap:AttackTarget(migs)
    end
    )
    :Spawn()
end

-- start after 10 mins, new enemies every 10 mins
myredtimer = TIMER:New(redinterceptors)
myredtimer:Start(600, 600)
