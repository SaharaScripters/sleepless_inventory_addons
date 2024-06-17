---@class CraftItem
---@field name string The name of the item.
---@field amount number The amount of the item involved in the craft.
---@field remove boolean Whether the item should be removed after the crafting process.
---@field slot number The slot number of the item in the inventory.

---@class CraftResult
---@field name string The name of the resulting item.
---@field amount number The amount of the resulting item.

---@class CraftQueueEntry
---@field costs table<string, CraftCost> The resources required for crafting, including their quantities and removal flags.
---@field result CraftResult[] The result of the crafting process.

local ox_inventory = exports.ox_inventory
local RECIPES = require 'dragCraft.config'

---@type table<number, CraftQueueEntry>
local CraftQueue = {}

local craftHook = ox_inventory:registerHook('swapItems', function(data)
    local fromSlot = data.fromSlot
    local toSlot = data.toSlot

    if type(fromSlot) == "table" and type(toSlot) == "table" then

        if fromSlot.name == toSlot.name then return end

        local recipeKey = string.format("%s %s", fromSlot.name, toSlot.name)
        local reverseRecipeKey = string.format("%s %s", toSlot.name, fromSlot.name)
        local recipeIndex = (RECIPES[recipeKey] and recipeKey) or (RECIPES[reverseRecipeKey] and reverseRecipeKey) or nil

        if not recipeIndex then return end

        local recipe = RECIPES[recipeIndex]
        local costs = recipe.costs
        for itemName, cost in pairs(costs) do
            if ox_inventory:GetItem(data.source, itemName, nil, true) < cost.need then
                local description = ("Not enough %s. Need %d"):format(itemName, cost.need)
                TriggerClientEvent('ox_lib:notify', data.source, { type = 'error', description = description })
                return false
            end
        end

        local resultForQueue = {}

        for i = 1, #recipe.result do
            local resultData = recipe.result[i]
            resultForQueue[i] = {
                name = resultData.name,
                amount = resultData.amount
            }
        end

        CraftQueue[data.source] = {
            costs = costs,
            result = resultForQueue
        }

        ---@type boolean | nil
        local continue = nil

        if recipe.server?.before then
            continue = recipe.server.before(recipe)
        end

        if continue == false then return false end

        TriggerClientEvent('dragCraft:Craft', data.source, recipe.duration, recipeIndex)

        return false
    end
end, {})

---@param source number player server id
---@param costs table<string, CraftCost>
---@return boolean
local function processCraftItems(source, costs)
    for itemName, craftItem in pairs(costs) do
        if craftItem.remove and not ox_inventory:RemoveItem(source, itemName, craftItem.need) then
            local description = ("You do not have enough %s to craft this item."):format(itemName)
            TriggerClientEvent('ox_lib:notify', source, { type = 'error', description = description })
            return false
        end
    end
    return true
end

---@param success boolean
---@param index string
RegisterNetEvent('dragCraft:success', function(success, index)
    local source = source --[[@as number]]
    local recipe = RECIPES[index]

    local queuedCraft = CraftQueue[source]

    if not queuedCraft then return end

    if success and processCraftItems(source, queuedCraft.costs) then
        for i = 1, #queuedCraft.result do
            local resultData = queuedCraft.result[i]
            ox_inventory:AddItem(source, resultData.name, resultData.amount)
        end

        if recipe.server.after then
            recipe.server.after(recipe)
        end
    end

    CraftQueue[source] = nil
end)


local function addRecipe(source, id, recipe, sync)
    recipe.client = nil
    RECIPES[id] = recipe

    if sync then return end

    lib.callback.await('dragCraft:client:addRecipe', source, id, recipe, true)
end

lib.callback.register('dragCraft:server:addRecipe', addRecipe)
exports('addRecipe', addRecipe)
