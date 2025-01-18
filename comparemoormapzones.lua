
function clean( zone )
	zone = string.lower(zone);
	zone = string.gsub(zone, "^the%s+", "");
	zone = string.gsub(zone, "^die%s+", "");
	zone = string.gsub(zone, "^das%s+", "");
	zone = string.gsub(zone, "[^a-z0-9]", "");
	return zone;
end
Turbine = { DataScope ={ Account = 1 } };
require('data/source/moormap/Defaults');
require('data/source/moormap/Strings');
class = function() return {} end
require('data/source/moormap/Table');
PatchDataSave = function() end
local mapData = {}
local moormapZones = {}
local moormapIdLookup = {}
LoadDefaults({}, mapData);
for i, rec in pairs(mapData) do
    local cleanMMName = clean(Resource[1][rec[2]]);
    -- if rec[2] == 655 then print("MM Zone: " .. Resource[1][rec[2]] .. ", Clean: " .. cleanMMName) end;
    moormapZones[cleanMMName] = { rec=rec, name=Resource[1][rec[2]] };
    moormapIdLookup[rec[2]] = Resource[1][rec[2]];
end

require('data/output/Compendium/Quests/CompendiumQuestsDB')
require('data/output/Compendium/Deeds/CompendiumDeedsDB')
local fh = io.open("zone-mismatches.json", "w")
local json = require 'lunajson'


local mismatch = {};
for i, rec in ipairs(questtable) do
    if rec.zone ~= nil then
        local cleanName = clean(rec.zone)
        if moormapZones[cleanName] == nil then
            mismatch[rec.zone] = "UNKNOWN";
        end
    end
end
for i, rec in ipairs(deedtable) do
    if rec.zone ~= nil then
        local cleanName = clean(rec.zone)
        if moormapZones[cleanName] == nil then
            mismatch[rec.zone] = "UNKNOWN";
        end
    end
end
local moormapZoneMismatch = {
    [228] = "Rohan - Eastemnet", -- East Rohan
    [277] = "Rohan - Wildermore", -- Wildermore
    [287] = "Rohan - Westemnet", -- Western Rohan
    [39] = "Forochel", -- Forochell
    [403] = "Imlad Morgul", -- Morgul Vale
    [512] = "Tales of Yore: Azanulbizar", -- Azanulbizar T.A.2977
    [635] = "Pinnath Gelin", -- Pinneth Gelin
    [638] = "The Shield Isles", -- Zîrar Tarka - The Shield Isles
    [639] = "Umbar", -- Cape of Umbar
    [642] = "Umbar-môkh", -- Umbar-môkh: the neaths
    [656] = "Urash Dâr", -- urush dâr
}
for zone, status in pairs(mismatch) do
    local mmName = "";
    for resourceId, name in pairs(moormapZoneMismatch) do
        if zone == name then
            mismatch[zone] = resourceId;
            status = resourceId;
            mmName = moormapIdLookup[resourceId];
        end
    end
    -- write out the id, zone, and mmName
    print(string.format("[%s] = \"%s\", -- %s", status, zone, mmName));
end

fh:write(json.encode(mismatch))
fh:close()
