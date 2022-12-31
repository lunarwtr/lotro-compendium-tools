
require('data/output/Compendium/Quests/CompendiumQuestsDB')

local json = require 'lunajson'
-- local fh = io.open("quest-commentdb.json", "w")
-- local comments = {};
-- for i, rec in ipairs(questtable) do
--     if rec.c ~= nil then
--         local name = rec.name:gsub("^Vol%. %w+, ", "");
--         comments[name .. '|' .. rec.category] = rec.c;
--     end
-- end
-- fh:write(json.encode(comments))
-- fh:close()

require('data/output/Compendium/Deeds/CompendiumDeedsDB')
local fh = io.open("deed-commentdb.json", "w")
local comments = {};
for i, rec in ipairs(deedtable) do
    if rec.c ~= nil then
        local name = rec.name;
        local subname, category = rec.name:match("^(.-)%s*%(([^%)]+)%)$");
        if subname ~= nil then
            comments[subname .. '|' .. rec.t .. '|' .. category] = rec.c;
        else
            comments[name .. '|' .. rec.t] = rec.c;
        end
    end
end
fh:write(json.encode(comments))
fh:close()