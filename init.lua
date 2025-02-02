local auto_refill = minetest.settings:get_bool("invtweak_auto_refill", true)

local tweak = {}
tweak.formspec = {}

local function comp_asc(w1, w2)
    return w1.name < w2.name
end

local function comp_desc(w1, w2)
    return w1.name > w2.name
end

-- Define sorting buttons
tweak.buttons = {
    "button[13.5,0.3;0.75,0.75;sort_asc;A]".."tooltip[sort_asc;Sort Items Ascending.;#30434C;#FFF]",
    "button[14.3,0.3;0.75,0.75;sort_desc;D]".."tooltip[sort_desc;Sort Items Descending.;#30434C;#FFF]",
    "button[15.1,0.3;0.75,0.75;sort_stack;M]".."tooltip[sort_stack;Stack Items and Sort Ascending.;#30434C;#FFF]"
}

local function add_buttons(formspec)
    if not formspec then return end
    for _, button in ipairs(tweak.buttons) do
        formspec = formspec .. button
    end
    return formspec
end

-- Add sorting buttons to various inventory forms
local inventory_mods = {"mcl_inventory", "mcl_chest", "mcl_chest_large", "mcl_barrel", "mcl_ender_chest", "unified_inventory"}
for _, mod in ipairs(inventory_mods) do
    if minetest.global_exists(mod) then
        local original_formspec = _G[mod].get_formspec
        _G[mod].get_formspec = function(...)
            return add_buttons(original_formspec(...))
        end
    end
end

minetest.register_on_player_receive_fields(function(player, formname, fields)
    if fields.sort_asc then tweak.sort(player, comp_asc) end
    if fields.sort_desc then tweak.sort(player, comp_desc) end
    if fields.sort_stack then tweak.sort(player, comp_asc, true) end
end)

-- Function to stack items properly
tweak.stack_items = function(list)
    local stacked = {}
    local item_map = {}

    for _, stack in ipairs(list) do
        if stack.name and stack.name ~= "" then
            if not item_map[stack.name] then
                item_map[stack.name] = {name = stack.name, count = 0, max = stack.max or 99}
            end
            item_map[stack.name].count = item_map[stack.name].count + stack.count
        end
    end

    for _, item in pairs(item_map) do
        while item.count > 0 do
            local take = math.min(item.count, item.max)
            table.insert(stacked, {name = item.name, count = take})
            item.count = item.count - take
        end
    end

    return stacked
end

tweak.sort = function(player, comparator, stack)
    local inv = player:get_inventory()
    if inv then
        local list = inv:get_list("main")
        local items = {}

        for i = 9, #list do
            local stack = list[i]
            if not stack:is_empty() then
                table.insert(items, {name = stack:get_name(), count = stack:get_count(), max = stack:get_stack_max()})
            end
        end

        if stack then
            items = tweak.stack_items(items)
        end

        table.sort(items, comparator)

        for i = 9, #list do
            local item = table.remove(items, 1)
            if item then
                inv:set_stack("main", i, ItemStack(item.name .. " " .. item.count))
            else
                inv:set_stack("main", i, nil)
            end
        end
    end
end

if auto_refill then
    minetest.register_on_placenode(function(pos, newnode, placer, oldnode)
        if not placer then return end
        local index = placer:get_wield_index()
        local cnt = placer:get_wielded_item():get_count() - 1
        if not minetest.settings:get_bool("creative_mode") and cnt == 0 then
            minetest.after(0.01, function()
                local inv = placer:get_inventory()
                if not inv then return end
                for i, stack in ipairs(inv:get_list("main")) do
                    if stack:get_name() == newnode.name then
                        inv:set_stack("main", index, stack)
                        stack:clear()
                        inv:set_stack("main", i, stack)
                        return
                    end
                end
            end)
        end
    end)
end

minetest.log("action", "[Inventory Tweaks] Loaded with Chest, Barrel, Ender Chest & Unified Inventory Support")

