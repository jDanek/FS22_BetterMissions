BetterMissions = {
	VERSION = g_modManager:getModByName(g_currentModName).version,
	MOD_NAME = g_currentModName,
	BASE_DIRECTORY = g_currentModDirectory,
	MOD_SETTINGS = getUserProfileAppPath() .. "modSettings",
	REWARD_PER_HOUR = 20000,
	DEBUG_MODE = false,
	STEP_VEHICLES = {
		CUTTERS = "HEADER",
		CORNHEADERS = "HEADER",
		BEETVEHICLES = "HEADER",
		COTTONVEHICLES = "HARVESTER",
		BEETHARVESTING = "HARVESTER",	
		POTATOHARVESTING = "HARVESTER",
		POTATOVEHICLES = "HARVESTER",
		SUGARCANEVEHICLES = "HARVESTER",
		VEGETABLEVEHICLES = "HARVESTER",
		VEGETABLETOOLS = "HARVESTER",
		PLOWS = "PLOW",
		SEEDERS = "SOW",
		PLANTERS = "SOW",
		SUGARCANEHARVESTING = "SOW",
		WEEDERS = "WEED",
		FERTILIZERSPREADERS = "FERTILIZE",
		SPRAYERS = "SPRAY",
		SPRAYERVEHICLES = "SPRAY",
		CULTIVATORS = "TILL",
		DISCHARROWS = "TILL",
		MOWERS = "MOW",
		TEDDERS = "TED",
		WINDROWERS = "RAKE",
		BALERS = "BALE",
		BALEWRAPPERS = "WRAP"
	},
	REIMBURSEMENTS_PER_HA = {
		NONE = 0,
		GRAIN = 450,
		MAIZE = 360,
		SUGARBEET = 360,
		POTATO = 3420,
		COTTON = 360,
		SUGARCANE = 1428,
		SPRAY = 0.0081,
		FERTILIZE = 0.0060
	},
	STARTUP_MODE = 1
}
local BetterMissions_mt = Class(BetterMissions)
addModEventListener(BetterMissions)

source(Utils.getFilename("events/BMGetExtendedMissionDataEvent.lua", BetterMissions.BASE_DIRECTORY))
source(Utils.getFilename("events/BMSendExtendedMissionDataEvent.lua", BetterMissions.BASE_DIRECTORY))
source(Utils.getFilename("events/BMUserConnectedEvent.lua", BetterMissions.BASE_DIRECTORY))

function BetterMissions:loadMap()
	BetterMissions.info("Loading Better Missions v" .. BetterMissions.VERSION)
	if fileExists(BetterMissions.MOD_SETTINGS .. "/BetterMissionsDebugMode") then
		BetterMissions.DEBUG_MODE = true
		BetterMissions.STARTUP_MODE = 2
	end
		
	--Overwrite Description Functions
    HarvestMission.getData = Utils.overwrittenFunction(HarvestMission.getData, BetterMissions.getHarvestMissionData)
	SprayMission.getData = Utils.overwrittenFunction(SprayMission.getData, BetterMissions.getSprayMissionData)
	BaleMission.getData = Utils.overwrittenFunction(BaleMission.getData, BetterMissions.getBaleMissionData)
	CultivateMission.getData = Utils.overwrittenFunction(CultivateMission.getData, BetterMissions.getCultivateMissionData)
	FertilizeMission.getData = Utils.overwrittenFunction(FertilizeMission.getData, BetterMissions.getFertilizeMissionData)
	PlowMission.getData = Utils.overwrittenFunction(PlowMission.getData, BetterMissions.getPlowMissionData)
	SowMission.getData = Utils.overwrittenFunction(SowMission.getData, BetterMissions.getSowMissionData)
	WeedMission.getData = Utils.overwrittenFunction(WeedMission.getData, BetterMissions.getWeedMissionData)
	if g_currentMission:getIsServer() then
		g_messageCenter:subscribe(MessageType.MISSION_GENERATED, BetterMissions.updateMissionRewards, BetterMissions)
		BetterMissions.DEBUG_MODE = true
		BetterMissions.STARTUP_MODE = 2
		Mission00.loadMission00Finished = Utils.appendedFunction(Mission00.loadMission00Finished, BetterMissions.MissionLoaded)
	end		
	addConsoleCommand("bmDebugToggle", "Toggle debug mode for Better Missions", "consoleToggleDebug", self)
	addConsoleCommand("bmDebugDumpTables", "Dumps Mission Tables", "consoleDumpTables", self)
	addConsoleCommand("bmDebugDumpMissionData", "Dumps Single Mission Data", "consoleDumpMissionData", self)
	--g_missionManager.MISSION_GENERATION_INTERVAL = 600000
end

function BetterMissions:MissionLoaded()
	--Calculate Mission data for missions that the server has alread generated
	BetterMissions:updateMissionRewards()
end

function BetterMissions:init()
	if g_server == nil then
		BMUserConnectedEvent.sendEvent()
	end
end

function BetterMissions:consoleToggleDebug()
	if BetterMissions.DEBUG_MODE == false then
		BetterMissions.DEBUG_MODE = true
	else
		BetterMissions.DEBUG_MODE = false
	end
	BetterMissions.info("Debug mode set to " .. tostring(BetterMissions.DEBUG_MODE))
end

function BetterMissions:consoleDumpTables()
	--BetterMissions.DumpTables(g_missionManager.missions)
	DebugUtil.printTableRecursively(g_missionManager.missions)
end

function BetterMissions:consoleDumpMissionData(fieldId)
	if fieldId == nil then
		print("Specify fieldId.  Example:  bmDebugDumpMissionData 10")
		return
	end
	local found = false
	for _,mission in pairs(g_missionManager.missions) do
		if mission.field.fieldId == tonumber(fieldId) then
			found = true
			DebugUtil.printTableRecursively(mission, ">>", 0, 1)
		end
	end
	if found == false then
		print("No mission found for field " .. fieldId)
	end
end

function BetterMissions.getMissionSteps(mission)
	local missionType = string.upper(mission.type.name)
	local fieldSize = string.upper(mission:getFieldSize())
	BetterMissions.debug("Processing " .. missionType .. " mission for field " .. mission.field.fieldId .. "(" .. mission.field.fieldArea .. "Ha)")
	local missionSteps = {}
	for i = 1, #mission.vehiclesToLoad do
		local storeItem = g_storeManager:getItemByXMLFilename(mission.vehiclesToLoad[i].filename)
		local stepName = BetterMissions.STEP_VEHICLES[storeItem.categoryName]
		BetterMissions.debug("[" .. mission.field.fieldId .. "] " .. missionType .. " :: " .. mission.vehiclesToLoad[i].filename .. " :: " .. storeItem.categoryName)
		if BetterMissions.STEP_VEHICLES[storeItem.categoryName] ~= nil then
			StoreItemUtil.loadSpecsFromXML(storeItem)
			local step = {
				speed = tonumber(Utils.getNoNil(storeItem.specs.speedLimit, 0)),
				width = tonumber(Utils.getNoNil(storeItem.specs.workingWidth, 0))
			}
			if step.width == 0 then
				if storeItem.name == "K105" or storeItem.name == "K165" then
					step.width = 12
				elseif storeItem.name == "Ventor 4150" then
					step.width = 3.3
				elseif storeItem.name == "COMMANDER 4500 DELTA FORCE" or storeItem.name == "AEON 5200 DELTA FORCE"  then
					step.width = 27
				elseif storeItem.name == "Rexor 6300 Platinum" then
					step.width = 2.8
				elseif storeItem.name == "Panther 2" then
					step.width = 2.7
				else
					BetterMissions.warning(storeItem.name .. " has a width of 0")
				end
			end
			BetterMissions.debug(storeItem.name .. " Speed: " .. step.speed .. " :: Width: " .. step.width)
			if storeItem.categoryName == "MOWERS" then
				if missionSteps.MOW == nil then
					missionSteps.MOW = step
				else
					missionSteps.MOW.speed = math.min(missionSteps.MOW.speed, step.speed)
					if fieldSize == "SMALL" then
						missionSteps.MOW.width = missionSteps.MOW.width + step.width
					elseif missionSteps.MOW.width < step.width then
						missionSteps.MOW.width = step.width
					end
				end
			elseif storeItem.categoryName == "POTATOHARVESTING" or storeItem.categoryName == "BEETHARVESTING" then
				if missionSteps.HARVESTER == nil then
					missionSteps.HARVESTER = step
				else
					if step.width > 0 then
						missionSteps.HARVESTER.width = math.min(missionSteps.HARVESTER.width, step.width)
					end
					if step.speed > 0 then
						missionSteps.HARVESTER.speed = math.min(missionSteps.HARVESTER.speed, step.speed)
					end
				end
			elseif storeItem.categoryName == "SPRAYERS" or storeItem.categoryName == "SEEDERS" or storeItem.categoryName == "PLANTERS" then
				--Ignore 0 width items (sprayer tanks, seed tanks/carts)
				if missionSteps[stepName] ~= nil then
					BetterMissions.debug("Step Name: " .. stepName .. ", current speed: " .. missionSteps[stepName].speed)
					BetterMissions.debug("Step Name: " .. stepName .. ", current width: " .. missionSteps[stepName].width)
					missionSteps[stepName].speed = math.max(missionSteps[stepName].speed, step.speed)
					missionSteps[stepName].width = math.max(missionSteps[stepName].width, step.width)
					BetterMissions.debug("Step Name: " .. stepName .. ", new speed: " .. missionSteps[stepName].speed)
					BetterMissions.debug("Step Name: " .. stepName .. ", new width: " .. missionSteps[stepName].width)
				else
					missionSteps[stepName] = step
				end
			else
				if missionSteps[stepName] ~= nil then
					if missionSteps[stepName].speed < step.speed or missionSteps[stepName].width < step.width then
						missionSteps[stepName] = step
					end
				else
					missionSteps[stepName] = step
				end
			end
		else
			BetterMissions.debug("Skipping " .. storeItem.categoryName .. " :: " .. mission.vehiclesToLoad[i].filename)
		end
	end

	--Fix Baler Speed and Wrapper Speed & Width if present
	if missionSteps.BALE ~= nil then
		missionSteps.BALE.width = missionSteps.RAKE.width
	end
	if missionSteps.WRAP ~= nil then
		missionSteps.WRAP.width = missionSteps.RAKE.width
		missionSteps.WRAP.speed = missionSteps.BALE.speed
	end

	mission.missionSteps = missionSteps
end

function BetterMissions.getMissionReimbursement(mission)
	local missionType = string.upper(mission.type.name)
	local step
	local reimbursementPerHa = 0
	if missionType == "SOW" then
		reimbursementPerHa = BetterMissions.REIMBURSEMENTS_PER_HA[mission:getVehicleVariant()]
	elseif missionType == "FERTILIZE" then
		step = mission.missionSteps.FERTILIZE
		reimbursementPerHa = ((BetterMissions.REIMBURSEMENTS_PER_HA.FERTILIZE * step.width * step.speed * 3600 * 1.6) / mission.haPerHour) * 1.1
	elseif missionType == "SPRAY" then
		step = mission.missionSteps.SPRAY
		reimbursementPerHa = ((BetterMissions.REIMBURSEMENTS_PER_HA.SPRAY * step.width * step.speed * 3600 * 1.2) / mission.haPerHour) * 1.1
	end
	return Utils.getNoNil(reimbursementPerHa, 0)
end

function BetterMissions.calculateNewRewards(mission)
	--Calculate haPerHour, expectedFieldTime, newBaseReward, newRewardPerHa
	local expectedTime = 0
	local implementHaPerHour
	BetterMissions.debug("Found " .. #mission.missionSteps .. " steps for field " .. mission.field.fieldId)
	if mission.type.name == "mow_bale" then
		for x,v in pairs(mission.missionSteps) do
			implementHaPerHour = (v.width * v.speed) / 10
			BetterMissions.debug("[" .. mission.field.fieldId .. "]" .. x .. " IHPH: " .. implementHaPerHour .. ", w: " .. v.width .. ", s:" .. v.speed)
			expectedTime = expectedTime + (mission.field.fieldArea / implementHaPerHour)
		end
	else
		for x,v in pairs(mission.missionSteps) do
			implementHaPerHour = (v.width * v.speed) / 10
			BetterMissions.debug("[" .. mission.field.fieldId .. "]" .. x .. " IHPH: " .. implementHaPerHour .. ", w: " .. v.width .. ", s:" .. v.speed)
			expectedTime = mission.field.fieldArea / implementHaPerHour
		end
	end

	
	mission.expectedFieldTime = expectedTime * 1.1
	mission.haPerHour = mission.field.fieldArea / expectedTime
	mission.newBaseReward = BetterMissions.REWARD_PER_HOUR * mission.expectedFieldTime
	mission.newRewardPerHa = mission.newBaseReward / mission.field.fieldArea

	--Get Reimbursement
	mission.newReimbursementPerHa = BetterMissions.getMissionReimbursement(mission)

	--Stow original bits for safekeeping
	mission.origReward = mission.reward
	mission.origRewardPerHa = mission.rewardPerHa
	mission.origReimbursementPerHa = mission.reimbursementPerHa

	--Get Fruit Multiplier
	local fruitMultiplier = 1
	if mission.field.fruitType ~= nil then
		local fruitDesc = g_fruitTypeManager:getFruitTypeByIndex(mission.field.fruitType)
		if fruitDesc ~= nil then
			fruitMultiplier = fruitDesc.missionMultiplier
		end
	end

	

	--Update Mission Rewards
	local displayReward = mission.rewardPerHa * mission.field.fieldArea * (1.3 - 0.1 * g_currentMission.missionInfo.economicDifficulty) + mission.reimbursementPerHa * mission.field.fieldArea * (1.4 - 0.1 * g_currentMission.missionInfo.economicDifficulty)
	mission.rewardPerHa = mission.newRewardPerHa
	mission.reimbursementPerHa = mission.newReimbursementPerHa
	local newReward = fruitMultiplier * mission.rewardPerHa * mission.field.fieldArea + mission.reimbursementPerHa * mission.field.fieldArea
	mission.reward = newReward
	local newDisplayReward = mission.rewardPerHa * mission.field.fieldArea * (1.3 - 0.1 * g_currentMission.missionInfo.economicDifficulty) + mission.reimbursementPerHa * mission.field.fieldArea * (1.4 - 0.1 * g_currentMission.missionInfo.economicDifficulty)
	mission.origDisplayReward = displayReward
	mission.newDisplayReward = newDisplayReward
	mission.BetterMissions = true
end

function BetterMissions.formatFieldTime(hours)
	if hours ~= nil then
		local totalSeconds = math.floor(hours * 3600)
		local hrs = math.floor(hours)
		local min = math.floor((hours - hrs) * 60)
		local sec = totalSeconds - (hrs * 3600) - (min * 60)
		return string.format("%02d:%02d:%02d", hrs, min, sec)
	else
		return "00:00:00"
	end
end

function BetterMissions:updateMissionRewards()
	if BetterMissions.STARTUP_MODE == 1 then
		--Enable Debug Mode for first run
		BetterMissions.DEBUG_MODE = true
	end
	BetterMissions.debug("Processing missions")
	for _,mission in pairs(g_missionManager.missions) do
		local stillValid = g_missionManager:canMissionStillRun(mission)
		if (stillValid) then
			if mission.BetterMissions == nil or mission.BetterMissions == false then
				BetterMissions.getMissionSteps(mission)
				BetterMissions.calculateNewRewards(mission)
				local fieldInfo = string.format([[Field Updated:
				Field Number:           %d
				Expected Time:          %s (%.3f)
				RewardPerHa:            $%d -> $%d
				BaseReward:             $%d -> $%d
				ReimbursementPerHa:     $%d -> $%d
				AdjustedReward:         $%d -> $%d]], mission.field.fieldId, BetterMissions.formatFieldTime(mission.expectedFieldTime), mission.expectedFieldTime, mission.origRewardPerHa, mission.newRewardPerHa, mission.origReward, mission.newBaseReward, mission.origReimbursementPerHa, mission.newReimbursementPerHa, mission.origDisplayReward, mission.newDisplayReward)
				BetterMissions.debug(fieldInfo)
				if g_server ~= nil then
					local event = BMSendExtendedMissionDataEvent.new(mission.field.fieldId, Utils.getNoNil(mission.expectedLiters, 0), Utils.getNoNil(mission.expectedFieldTime, 0))
					g_server:broadcastEvent(event, true)
				end
			else
				BetterMissions.debug(string.format("Skipping %s mission for field %02d. It has already been updated.", string.upper(mission.type.name), mission.field.fieldId))
			end
		else
			BetterMissions.debug(string.format("%s mission for field %02d is no longer valid.", string.upper(mission.type.name), mission.field.fieldId))
			mission.BetterMissions = false
		end
	end
	if BetterMissions.STARTUP_MODE == 1 then
		BetterMissions.STARTUP_MODE = 0
		BetterMissions.DEBUG_MODE = false
	end
end

function BetterMissions:getMissionReward(mission)
	if mission.BetterMissions == nil or mission.BetterMissions == false then
		BetterMissions.debug("Fetching Mission Info for field " .. mission.field.fieldId)
		BetterMissions.getMissionSteps(mission)
		BetterMissions.calculateNewRewards(mission)
		BetterMissions.debug(string.format("Mission for field %d updated: $%d --> $%d", mission.field.fieldId, mission.origDisplayReward, mission.newDisplayReward))
	end
end

function BetterMissions:getExtendedMissionData(fieldId)
	if g_currentMission:getIsServer() == false then
		--BetterMissions.debug("getExtendedMissionData -> Client (" .. fieldId .. ")")
		--Only Run if Client
		local currentMission = nil
		local currentMissionType = nil
		for _,mission in pairs(g_missionManager.missions) do
			if mission.field.fieldId == fieldId then
				local stillValid = g_missionManager:canMissionStillRun(mission)
				if (stillValid) then
					currentMission = mission
					currentMissionType = string.upper(mission.type.name)
				end
			end
		end
		if currentMission ~= nil then
			local updateInfo = false
			BetterMissions.debug("getExtendedMissionData->updateInfo: " .. tostring(updateInfo))
			if currentMission.expectedFieldTime == nil then
				updateInfo = true
			else
				BetterMissions.debug("getExtendedMissionData->currentMission.expectedFieldTime: " .. currentMission.expectedFieldTime)
			end
			if currentMissionType == "HARVEST" then
				if currentMission.expectedLiters == nil then
					updateInfo = true
				else
					BetterMissions.debug("getExtendedMissionData->currentMission.expectedLiters: " .. currentMission.expectedLiters)
				end
			else
				currentMission.expectedLiters = 0
			end
			BetterMissions.debug("getExtendedMissionData->updateInfo: " .. tostring(updateInfo))
			if updateInfo == true then
				g_client:getServerConnection():sendEvent(BMGetExtendedMissionDataEvent.new(currentMission.field.fieldId))
			end
		else
			--BetterMissions.warning("No mission found for field " .. fieldId)
		end
	else
		BetterMissions.debug("getExtendedMissionData -> Server")
	end
end

function BetterMissions:getWeedMissionData()
	if self.expectedFieldTime == nil then
		g_client:getServerConnection():sendEvent(BMGetExtendedMissionDataEvent.new(self.field.fieldId))
	end
	--BetterMissions:getExtendedMissionData(self.field.fieldId)
	return {
		location = string.format(g_i18n:getText("fieldJob_number"), self.field.fieldId),
		jobType = g_i18n:getText("fieldJob_jobType_weeding"),
		action = g_i18n:getText("fieldJob_desc_action_weeding"),
		description = string.format(g_i18n:getText("BM_fieldJob_desc_weeding"), self.field.fieldId, BetterMissions.formatFieldTime(self.expectedFieldTime))
	}
end

function BetterMissions:getHarvestMissionData()
	if self.expectedFieldTime == nil then
		g_client:getServerConnection():sendEvent(BMGetExtendedMissionDataEvent.new(self.field.fieldId))
	end
	--BetterMissions:getExtendedMissionData(self.field.fieldId)
    if self.sellPointId ~= nil then
		self:tryToResolveSellPoint()
	end

	local name = "Unknown"

	if self.sellPoint ~= nil then
		name = self.sellPoint:getName()
	end

	return {
		location = string.format(g_i18n:getText("fieldJob_number"), self.field.fieldId),
		jobType = g_i18n:getText("fieldJob_jobType_harvesting"),
		action = g_i18n:getText("fieldJob_desc_action_harvesting"),
		description = string.format(g_i18n:getText("BM_fieldJob_desc_harvesting"),Utils.getNoNil(self.expectedLiters, 0), g_fillTypeManager:getFillTypeByIndex(self.fillType).title, self.field.fieldId, name, BetterMissions.formatFieldTime(self.expectedFieldTime))
	}
end

function BetterMissions:getSprayMissionData()
	if self.expectedFieldTime == nil then
		g_client:getServerConnection():sendEvent(BMGetExtendedMissionDataEvent.new(self.field.fieldId))
	end
	--BetterMissions:getExtendedMissionData(self.field.fieldId)
	return {
		location = string.format(g_i18n:getText("fieldJob_number"), self.field.fieldId),
		jobType = g_i18n:getText("fieldJob_jobType_spraying"),
		action = g_i18n:getText("fieldJob_desc_action_spraying"),
		description = string.format(g_i18n:getText("BM_fieldJob_desc_spraying"), self.field.fieldId, BetterMissions.formatFieldTime(self.expectedFieldTime)),
		extraText = string.format(g_i18n:getText("fieldJob_desc_fillTheUnit"), g_fillTypeManager:getFillTypeByIndex(FillType.HERBICIDE).title)
	}
end

function BetterMissions:getBaleMissionData()
	if self.expectedFieldTime == nil then
		g_client:getServerConnection():sendEvent(BMGetExtendedMissionDataEvent.new(self.field.fieldId))
	end
	--BetterMissions:getExtendedMissionData(self.field.fieldId)
	if self.sellPointId ~= nil then
		self:tryToResolveSellPoint()
	end

	local l10nString = nil

	if self.fillType == FillType.SILAGE then
		l10nString = "BM_fieldJob_desc_baling_silage"
	else
		l10nString = "BM_fieldJob_desc_baling_hay"
	end

	return {
		location = string.format(g_i18n:getText("fieldJob_number"), self.field.fieldId),
		jobType = g_i18n:getText("fieldJob_jobType_baling"),
		action = g_i18n:getText("fieldJob_desc_action_baling"),
		description = string.format(g_i18n:getText(l10nString), self.field.fieldId, self.sellPoint:getName(), BetterMissions.formatFieldTime(self.expectedFieldTime))
	}
end

function BetterMissions:getCultivateMissionData()
	if self.expectedFieldTime == nil then
		g_client:getServerConnection():sendEvent(BMGetExtendedMissionDataEvent.new(self.field.fieldId))
	end
	--BetterMissions:getExtendedMissionData(self.field.fieldId)
	return {
		location = string.format(g_i18n:getText("fieldJob_number"), self.field.fieldId),
		jobType = g_i18n:getText("fieldJob_jobType_cultivating"),
		action = g_i18n:getText("fieldJob_desc_action_cultivating"),
		description = string.format(g_i18n:getText("BM_fieldJob_desc_cultivating"), self.field.fieldId, BetterMissions.formatFieldTime(self.expectedFieldTime))
	}
end

function BetterMissions:getFertilizeMissionData()
	if self.expectedFieldTime == nil then
		g_client:getServerConnection():sendEvent(BMGetExtendedMissionDataEvent.new(self.field.fieldId))
	end
	--BetterMissions:getExtendedMissionData(self.field.fieldId)
	return {
		location = string.format(g_i18n:getText("fieldJob_number"), self.field.fieldId),
		jobType = g_i18n:getText("fieldJob_jobType_fertilizing"),
		action = g_i18n:getText("fieldJob_desc_action_fertilizing"),
		description = string.format(g_i18n:getText("BM_fieldJob_desc_fertilizing"), self.field.fieldId, BetterMissions.formatFieldTime(self.expectedFieldTime)),
		extraText = string.format(g_i18n:getText("fieldJob_desc_fillTheUnit"), g_fillTypeManager:getFillTypeByIndex(FillType.FERTILIZER).title)
	}
end

function BetterMissions:getPlowMissionData()
	if self.expectedFieldTime == nil then
		g_client:getServerConnection():sendEvent(BMGetExtendedMissionDataEvent.new(self.field.fieldId))
	end
	--BetterMissions:getExtendedMissionData(self.field.fieldId)
	return {
		location = string.format(g_i18n:getText("fieldJob_number"), self.field.fieldId),
		jobType = g_i18n:getText("fieldJob_jobType_plowing"),
		action = g_i18n:getText("fieldJob_desc_action_plowing"),
		description = string.format(g_i18n:getText("BM_fieldJob_desc_plowing"), self.field.fieldId, BetterMissions.formatFieldTime(self.expectedFieldTime))
	}
end

function BetterMissions:getSowMissionData()
	if self.expectedFieldTime == nil then
		g_client:getServerConnection():sendEvent(BMGetExtendedMissionDataEvent.new(self.field.fieldId))
	end
	--BetterMissions:getExtendedMissionData(self.field.fieldId)
	return {
		location = string.format(g_i18n:getText("fieldJob_number"), self.field.fieldId),
		jobType = g_i18n:getText("fieldJob_jobType_sowing"),
		action = g_i18n:getText("fieldJob_desc_action_sowing"),
		description = string.format(g_i18n:getText("BM_fieldJob_desc_sowing"), self.field.fieldId, g_fruitTypeManager:getFillTypeByFruitTypeIndex(self.fruitType).title, BetterMissions.formatFieldTime(self.expectedFieldTime)),
		extraText = string.format(g_i18n:getText("fieldJob_desc_fillTheUnit"), g_fillTypeManager:getFillTypeByIndex(FillType.SEEDS).title)
	}
end

function BetterMissions.addModTranslations(i18n)
    local global = getfenv(0).g_i18n.texts

	for key, text in pairs(i18n.texts) do
		global[key] = text
	end
end

function BetterMissions.onMissionWillLoad(i18n)
	BetterMissions.addModTranslations(i18n)
end

function BetterMissions.DumpTables(table)
	print("Dumping table " ..  tostring(table))
	local name = tostring(table)
	name = string.gsub(name, ":", "")
	local exportFilename = g_currentMission.missionInfo.savegameDirectory .. "/" .. name
	local file = createFile(exportFilename, FileAccess.WRITE)
	BetterMissions.dumpTable(table, 0, file)
	delete(file)
end

function BetterMissions.dumpTable(table, depth, file)
	if depth > 4 then
		return
	end

	local indent = ""
	for c = 0, depth do
		indent = indent .. "|  "
	end
	for i,j in pairs(table) do
		fileWrite(file, indent .. tostring(i) .. " :: " ..tostring(j) .. "\n")
		if type(j) == "table" then
			BetterMissions.dumpTable(j, depth + 1, file)
		end
	end
end

function BetterMissions.info(message)
	print("[BM]::INFO    " .. tostring(message))
end

function BetterMissions.warning(message)
	print("[BM]::WARNING " .. tostring(message))
end

function BetterMissions.error(message)
	print("[BM]::ERROR   " .. tostring(message))
end

function BetterMissions.debug(message)
	if BetterMissions.DEBUG_MODE == true then
		print("[BM]::DEBUG   " .. tostring(message))
	end
end

function BetterMissions.printTableRecursivelyToXML(value,parentName, depth, maxDepth,xmlFile,baseKey)
	depth = depth or 0
	maxDepth = maxDepth or 3
	if depth > maxDepth then
		return
	end
	local key = string.format('%s.depth:%d',baseKey,depth)
	local k = 0
	for i,j in pairs(value) do
		local key = string.format('%s(%d)',key,k)
		local valueType = type(j) 
		setXMLString(xmlFile, key .. '#valueType', tostring(valueType))
		setXMLString(xmlFile, key .. '#index', tostring(i))
		setXMLString(xmlFile, key .. '#value', tostring(j))
		setXMLString(xmlFile, key .. '#parent', tostring(parentName))
		if valueType == "table" then
			BetterMissions.printTableRecursivelyToXML(j,parentName.."."..tostring(i),depth+1, maxDepth,xmlFile,key)
		end
		k = k + 1
	end
end
