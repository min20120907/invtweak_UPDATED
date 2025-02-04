----------------------------------
-- 設定檔：是否啟用自動補充
----------------------------------
local auto_refill = minetest.settings:get_bool("invtweak_auto_refill", true)

----------------------------------
-- 主要表單/界面增強(排序按鈕)
----------------------------------
local tweak = {}
tweak.formspec = {}

local function comp_asc(w1, w2)
    return w1.name < w2.name
end

local function comp_desc(w1, w2)
    return w1.name > w2.name
end

-- 定義排序按鈕
tweak.buttons = {
    "button[13.5,0.3;0.75,0.75;sort_asc;A]"..
        "tooltip[sort_asc;Sort Items Ascending.;#30434C;#FFF]",
    "button[14.3,0.3;0.75,0.75;sort_desc;D]"..
        "tooltip[sort_desc;Sort Items Descending.;#30434C;#FFF]",
    "button[15.1,0.3;0.75,0.75;sort_stack;M]"..
        "tooltip[sort_stack;Stack Items and Sort Ascending.;#30434C;#FFF]"
}

local function add_buttons(formspec)
    if not formspec then
        return
    end
    for _, button in ipairs(tweak.buttons) do
        formspec = formspec .. button
    end
    return formspec
end

-- 在幾個常見的存取介面加上排序按鈕
local inventory_mods = {
    "mcl_inventory",
    "mcl_chest",
    "mcl_chest_large",
    "mcl_barrel",
    "mcl_ender_chest",
    "unified_inventory"
}
for _, mod in ipairs(inventory_mods) do
    if minetest.global_exists(mod) then
        local original_formspec = _G[mod].get_formspec
        _G[mod].get_formspec = function(...)
            return add_buttons(original_formspec(...))
        end
    end
end

----------------------------------
-- 接收玩家表單事件（觸發排序）
----------------------------------
minetest.register_on_player_receive_fields(function(player, formname, fields)
    if fields.sort_asc then
        tweak.sort(player, comp_asc)
    end
    if fields.sort_desc then
        tweak.sort(player, comp_desc)
    end
    if fields.sort_stack then
        tweak.sort(player, comp_asc, true)
    end
end)

----------------------------------
-- 堆疊 item 的函式
----------------------------------
tweak.stack_items = function(list)
    local stacked = {}
    local item_map = {}

    for _, stack in ipairs(list) do
        if stack.name and stack.name ~= "" then
            if not item_map[stack.name] then
                item_map[stack.name] = {
                    name = stack.name,
                    count = 0,
                    max = stack.max or 99
                }
            end
            item_map[stack.name].count = item_map[stack.name].count + stack.count
        end
    end

    for _, item in pairs(item_map) do
        while item.count > 0 do
            local take = math.min(item.count, item.max)
            table.insert(stacked, {
                name = item.name,
                count = take
            })
            item.count = item.count - take
        end
    end

    return stacked
end

----------------------------------
-- 排序函式（可選擇是否先將物品 stack）
----------------------------------
tweak.sort = function(player, comparator, do_stack)
    local inv = player:get_inventory()
    if inv then
        local list = inv:get_list("main")
        local items = {}

        -- 只排序主背包中的第 9 格之後（前面 1~8 通常是熱鍵列）
        for i = 9, #list do
            local st = list[i]
            if not st:is_empty() then
                table.insert(items, {
                    name = st:get_name(),
                    count = st:get_count(),
                    max = st:get_stack_max()
                })
            end
        end

        if do_stack then
            items = tweak.stack_items(items)
        end

        table.sort(items, comparator)

        -- 再放回背包
        for i = 9, #list do
            local it = table.remove(items, 1)
            if it then
                inv:set_stack("main", i, ItemStack(it.name .. " " .. it.count))
            else
                inv:set_stack("main", i, nil)
            end
        end
    end
end

----------------------------------
-- 自動補充 (auto refill)
----------------------------------
local function refill(player, item_name, index)
    local inv = player:get_inventory()
    if not inv then
        return
    end
    -- 在 "main" 裡面找相同道具，移到原槽位
    local list = inv:get_list("main") or {}
    for i, stack in ipairs(list) do
        if stack:get_name() == item_name then
            inv:set_stack("main", index, stack)
            -- 將原先在該格的 stack 清空後，放到原本位置（相當於移動）
            stack:clear()
            inv:set_stack("main", i, stack)
            minetest.log("action", "[Inventory Tweaks] Auto-refilled "..
                item_name.." for "..player:get_player_name())
            return
        end
    end
end

if auto_refill then
    -- 當玩家放置方塊後，如果手上物品剛好用完，嘗試補充
    minetest.register_on_placenode(function(pos, newnode, placer, oldnode, itemstack, pointed_thing)
        if not placer then
            return
        end
        local index = placer:get_wield_index()
        local cnt = placer:get_wielded_item():get_count() - 1

        -- 如果不是創造模式，而且手上道具用完了(=0)，嘗試自動補充
        if not minetest.settings:get_bool("creative_mode") and cnt == 0 then
            minetest.after(0.01, refill, placer, newnode.name, index)
        end
    end)
end

----------------------------------
-- 取出背包中所有 item_name 的物品數量並清除
----------------------------------
local function take_all_from_inventory(inv, item_name)
    local total = 0
    local list = inv:get_list("main") or {}
    for _, stack in ipairs(list) do
        if stack:get_name() == item_name then
            total = total + stack:get_count()
        end
    end
    if total == 0 then
        return 0
    end
    -- 一次 remove_item(total 數量)
    local removed_stack = inv:remove_item("main", ItemStack(item_name.." "..total))
    return removed_stack:get_count()
end

----------------------------------
-- Pick Block 核心邏輯
----------------------------------
local function pick_block_action(player, node_name)
    local inv = player:get_inventory()
    if not inv then
        return
    end

    local idx = player:get_wield_index()        -- 玩家手上那個欄位
    local old_stack = inv:get_stack("main", idx)
    local old_count = old_stack:get_count()

    -- 把背包裡的該物品全拿出（注意之後要處理超過疊放上限）
    local removed_count = take_all_from_inventory(inv, node_name)
    if removed_count < 1 then
        return
    end

    -- 手上先清空（準備放新的方塊疊）
    inv:set_stack("main", idx, nil)

    -- 取得該物品本身的疊放上限 (在 MCL 中通常是 64)
    local def = minetest.registered_items[node_name]
    local stack_max = (def and def.stack_max) or 64

    -- 先放一疊(最多 stack_max)到手上
    local to_hand = math.min(removed_count, stack_max)
    local new_stack = ItemStack(node_name)
    new_stack:set_count(to_hand)
    inv:set_stack("main", idx, new_stack)

    -- 如果背包還有多餘的，放回背包（塞不下就掉落）
    local leftover_count = removed_count - to_hand
    if leftover_count > 0 then
        local leftover_stack = ItemStack(node_name)
        leftover_stack:set_count(leftover_count)
        leftover_stack = inv:add_item("main", leftover_stack)
        if not leftover_stack:is_empty() then
            local ppos = player:get_pos()
            minetest.item_drop(leftover_stack, player, ppos)
        end
    end

    -- 把玩家原先手上的舊物品加回背包，若背包滿則掉落
    if old_count > 0 then
        local leftover = inv:add_item("main", old_stack)
        if not leftover:is_empty() then
            local ppos = player:get_pos()
            minetest.item_drop(leftover, player, ppos)
        end
    end
end

----------------------------------
-- 幫助我們將「方塊名」轉成對應「物品名」
-- 有些節點放下去之後的 node.name 與 item.name 可能不同
-- 這裡嘗試用 get_node_drops() 取第一個掉落物。
-- 若你在 MineClone 中需要更準確處理，可以檢查 node_def._mcl_item
----------------------------------
local function get_item_name_from_node(node_name)
    -- 先用 get_node_drops 取看看
    local drops = minetest.get_node_drops(node_name, "")
    -- 若至少有一個掉落物，就以第一項做為對應物品
    if #drops > 0 then
        return drops[1]
    end
    -- 如果沒有，就直接回傳 node_name（最少不會報錯）
    return node_name
end

----------------------------------
-- Pick Block 觸發：需要 aux1 + 右鍵 同時按下
----------------------------------
local pick_cooldown = {}

minetest.register_globalstep(function(dtime)
    for _, player in ipairs(minetest.get_connected_players()) do
        local ctrl = player:get_player_control()
        -- ctrl.aux1 為輔助鍵（默認中鍵），ctrl.place 為右鍵
        if ctrl.aux1 and ctrl.place then
            -- 如果之前沒按著，才執行一次(避免連續判定)
            if not pick_cooldown[player] then
                pick_cooldown[player] = true

                local pname = player:get_player_name()
                local pos_eye = vector.add(player:get_pos(), {x=0, y=1.625, z=0})
                local dir = player:get_look_dir()
                local max_dist = 5
                local end_pos = vector.add(pos_eye, vector.multiply(dir, max_dist))

                -- 射线檢測：找玩家視線所指的 node
                local ray = minetest.raycast(pos_eye, end_pos, true, false)
                for pointed_thing in ray do
                    if pointed_thing.type == "node" then
                        local node = minetest.get_node_or_nil(pointed_thing.under)
                        if node and node.name ~= "air" then
                            -- 先轉換對應的物品 ID（以解決竹子等放置後 ID 不同問題）
                            local item_name = get_item_name_from_node(node.name)

                            -- 執行 pick block 動作
                            pick_block_action(player, item_name)
                        end
                        break
                    end
                end
            end
        else
            -- 沒有同時按住 aux1+右鍵，就重置
            pick_cooldown[player] = false
        end
    end
end)

minetest.log("action", "[Inventory Tweaks] Loaded with MCL Inventory (Survival), Chest, Barrel, Ender Chest & UI Support.")
