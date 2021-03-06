
require('data/output/Compendium/Quests/CompendiumQuestsDB')

local json = require 'lunajson'
local fh = io.open("commentdb.json", "w")
local comments = {};
for i, rec in ipairs(questtable) do
    if rec.c ~= nil then
        local name = rec.name:gsub("^Vol%. %w+, ", "");
        comments[name .. '|' .. rec.category] = rec.c;
    end
end
fh:write(json.encode(comments))
fh:close()