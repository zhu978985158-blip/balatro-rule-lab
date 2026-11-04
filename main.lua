local mod = SMODS.current_mod
local RuleLab = {}
_G.RuleLab = RuleLab

local defaults = {
    free_first_buy = false,
    sellback_plus = false,
    shop_echo = false,
    extra_action = false,
    first_hand_echo = false,
    universal_rewrite = false,
    joker_overclock = false,
    vanilla_ascension = false,
    edition_amplifier = false,
    blind_bailout = false,
    boss_reroll = false,
    no_discard_reward = false,
}

local labels = {
    free_first_buy = {"首购免费", "每个商店第一件购买物品价格为 $0。"},
    sellback_plus = {"增强回收", "出售 Joker 或消耗牌时额外获得 $2。"},
    shop_echo = {"商店回声", "重掷商店后，新商店第一格复制上一商店的一件 Joker。"},
    extra_action = {"额外行动", "每回合额外获得 1 次出牌和 1 次弃牌。"},
    first_hand_echo = {"首手回响", "每个盲注的第一手牌获得 1.5 倍计分。"},
    universal_rewrite = {"万能改写", "每个盲注第一次出牌直接按 Straight Flush 结算牌型。"},
    joker_overclock = {"Joker 超频", "每个 Joker 每回合第一次触发时追加一次触发。"},
    vanilla_ascension = {"原版升阶", "原版 Joker 返回的数值效果翻倍；Blueprint 与 Brainstorm 不重复放大。"},
    edition_amplifier = {"Edition 放大", "Foil、Holographic、Polychrome、Negative 的效果翻倍。"},
    blind_bailout = {"失败保底", "每局第一次失败的盲注自动视为通过。"},
    boss_reroll = {"Boss 重选", "每个 Boss 盲注免费追加一次重选。"},
    no_discard_reward = {"无弃牌奖励", "不使用弃牌击败盲注时，下一回合获得 1 次出牌和 $3。"},
}

local function copy_config()
    local result = {}
    for key, default in pairs(defaults) do
        result[key] = mod.config and mod.config[key] == true or default
    end
    return result
end

local function copy_edition(edition)
    if not edition then return nil end
    local result = {}
    for key, value in pairs(edition) do result[key] = value end
    return result
end

local function is_number(value)
    return type(value) == 'number'
end

function RuleLab.state()
    if not G or not G.GAME then return nil end
    return G.GAME.rule_lab
end

function RuleLab.ensure_state()
    if not G or not G.GAME then return nil end
    local state = G.GAME.rule_lab
    if not state then
        state = {
            config = copy_config(),
            initialized = false,
            bailout_used = false,
            boss_reroll_used = false,
            shop_first_purchase_used = false,
            first_hand_echo_used = false,
            universal_rewrite_used = false,
            overclock_seen = {},
            shop_echo = nil,
        }
        G.GAME.rule_lab = state
    end
    state.config = state.config or copy_config()
    state.overclock_seen = state.overclock_seen or {}
    return state
end

function RuleLab.enabled(key)
    local state = RuleLab.state()
    return state and state.config and state.config[key] == true
end

function RuleLab.reset_round_state()
    local state = RuleLab.ensure_state()
    if not state then return end
    state.first_hand_echo_used = false
    state.universal_rewrite_used = false
    state.overclock_seen = {}
    state.shop_first_purchase_used = false
    state.boss_reroll_used = false
    state.shop_echo = nil
    state.extra_action_granted = false
end

function RuleLab.reset_game_globals(run_start)
    local state = RuleLab.ensure_state()
    if not state then return end

    if run_start then
        -- Keep the snapshot when loading a save; only new runs read the menu again.
        if not state.initialized then
            state.config = copy_config()
            state.initialized = true
            state.bailout_used = false
        end
        state.overclock_seen = {}
        return
    end

    RuleLab.reset_round_state()
    G.GAME.round_bonus = G.GAME.round_bonus or {next_hands = 0, discards = 0}


    if RuleLab.enabled('no_discard_reward') and G.GAME.current_round and (G.GAME.current_round.discards_used or 0) == 0 then
        G.GAME.round_bonus.next_hands = (G.GAME.round_bonus.next_hands or 0) + 1
        ease_dollars(3)
    end
end

function RuleLab.can_free_purchase(card)
    return card and RuleLab.enabled('free_first_buy') and not RuleLab.state().shop_first_purchase_used
end

function RuleLab.after_purchase(card, was_free)
    local state = RuleLab.state()
    if state and was_free then state.shop_first_purchase_used = true end
end

function RuleLab.after_sale(card)
    if RuleLab.enabled('sellback_plus') then ease_dollars(2) end
end

function RuleLab.capture_shop_echo()
    if not RuleLab.enabled('shop_echo') or not G.shop_jokers or not G.shop_jokers.cards[1] then return end
    local card = G.shop_jokers.cards[1]
    local center = card.config and card.config.center
    if not center or not center.key or card.ability.set ~= 'Joker' then return end
    local state = RuleLab.state()
    state.shop_echo = {
        key = center.key,
        edition = copy_edition(card.edition),
    }
end

function RuleLab.take_shop_echo(area)
    local state = RuleLab.state()
    if area ~= G.shop_jokers or not state or not state.shop_echo then return nil end
    local echo = state.shop_echo
    state.shop_echo = nil
    return echo
end

function RuleLab.boss_reroll_available()
    return RuleLab.enabled('boss_reroll') and not RuleLab.state().boss_reroll_used
end

function RuleLab.consume_boss_reroll()
    if not RuleLab.boss_reroll_available() then return false end
    RuleLab.state().boss_reroll_used = true
    return true
end

function RuleLab.try_bailout()
    local state = RuleLab.state()
    if not state or not RuleLab.enabled('blind_bailout') or state.bailout_used then return false end
    state.bailout_used = true
    if G.GAME and G.GAME.blind and G.GAME.blind.chips then
        G.GAME.chips = G.GAME.blind.chips
    end
    -- Let the normal SMODS saved-round path handle the transition.  Merely
    -- changing chips after end_of_round has already run can leave the game in
    -- HAND_PLAYED with no matching round-evaluation event.
    if SMODS then SMODS.saved = true end
    if G.GAME then G.GAME.saved_text = '规则实验室：失败保底' end
    return true
end

local function scale_effect(effect, key, multiplier)
    if is_number(effect[key]) then effect[key] = effect[key] * multiplier end
end

function RuleLab.is_vanilla_joker(card)
    if not card or not card.ability or card.ability.set ~= 'Joker' then return false end
    if not card.config or not card.config.center then return false end
    if card.config.center.mod then return false end
    return type(card.config.center.key) == 'string' and card.config.center.key:sub(1, 2) == 'j_'
end

function RuleLab.after_joker_calculate(card, context, result)
    if not result or type(result) ~= 'table' then return result end
    local state = RuleLab.state()
    if not state then return result end

    if RuleLab.enabled('vanilla_ascension') and RuleLab.is_vanilla_joker(card)
        and card.ability.name ~= 'Blueprint' and card.ability.name ~= 'Brainstorm'
        and not context.blueprint and not context.retrigger_joker then
        for _, key in ipairs({'mult_mod', 'chip_mod', 'mult', 'chips', 'dollars', 'p_dollars', 'h_mult', 'h_chips', 'h_dollars'}) do
            scale_effect(result, key, 2)
        end
        scale_effect(result, 'Xmult_mod', 2)
        scale_effect(result, 'x_mult', 2)
    end

    if RuleLab.enabled('joker_overclock') and not context.blueprint and not context.retrigger_joker
        and not context.repetition and (context.joker_main or context.individual or context.using_consumeable) then
        local card_key = card.sort_id or tostring(card)
        if not state.overclock_seen[card_key] then
            state.overclock_seen[card_key] = true
            result.repetitions = (result.repetitions or 0) + 1
        end
    end

    return result
end

function RuleLab.edition_effect(card)
    if not card or not card.edition then return nil end
    local edition = card.edition
    if edition.foil then return {chips = (G.P_CENTERS.e_foil.config.extra or 50), message = 'Edition 放大'} end
    if edition.holo then return {mult = (G.P_CENTERS.e_holo.config.extra or 10), message = 'Edition 放大'} end
    if edition.polychrome then return {Xmult_mod = (G.P_CENTERS.e_polychrome.config.extra or 1.5), message = 'Edition 放大'} end
    return nil
end

function RuleLab.calculate(self, context)
    local state = RuleLab.state()
    if not state or not context then return nil end

    if RuleLab.enabled('first_hand_echo') and context.joker_main
        and not state.first_hand_echo_used and G.GAME.current_round
        and (G.GAME.current_round.hands_played or 0) == 0 then
        state.first_hand_echo_used = true
        return {Xmult_mod = 1.5, message = '首手回响', colour = G.C.MONEY}
    end

    if RuleLab.enabled('edition_amplifier') and (context.individual or context.edition)
        and (context.cardarea == G.play or context.cardarea == G.jokers or context.edition) then
        local effect = RuleLab.edition_effect(context.other_card or context.card or context.scored_card)
        if effect then return effect end
    end

    return nil
end

mod.reset_game_globals = RuleLab.reset_game_globals
mod.calculate = RuleLab.calculate


-- Run changes are stored in G.GAME.rule_lab; menu changes are defaults for new runs.
function RuleLab.in_run()
    return G and G.STAGE == G.STAGES.RUN and G.GAME ~= nil
end

function RuleLab.grant_extra_action()
    local state = RuleLab.ensure_state()
    if not state or not RuleLab.enabled('extra_action') or state.extra_action_granted then return end
    if not G.GAME.blind or not G.GAME.blind.in_blind then return end
    state.extra_action_granted = true
    ease_hands_played(1, true)
    ease_discard(1, true)
end

-- Use Steamodded's per-card slot contribution so existing Negative cards update
-- immediately and the contribution survives save/load with the card's ability.
function RuleLab.sync_negative(card)
    if not card or not card.ability then return end
    local area = card.ability.consumeable and G.consumeables or G.jokers
    if card.rule_lab_negative_slot then
        -- Migrate the 0.1.0 direct area adjustment once.
        if area then area.config.card_limit = area.config.card_limit - 1 end
        card.rule_lab_negative_slot = nil
    end
    local old = card.ability.rule_lab_negative_bonus or 0
    local desired = (RuleLab.enabled('edition_amplifier') and card.added_to_deck
        and card.edition and card.edition.negative
        and (card.ability.set == 'Joker' or card.ability.consumeable)) and 1 or 0
    card.ability.card_limit = (card.ability.card_limit or 0) + desired - old
    card.ability.rule_lab_negative_bonus = desired ~= 0 and desired or nil
    if area and area.handle_card_limit then area:handle_card_limit() end
end

local set_edition_ref = Card.set_edition
function Card:set_edition(...)
    local result = set_edition_ref(self, ...)
    RuleLab.sync_negative(self)
    return result
end

function RuleLab.set_live_rule(key, value)
    if defaults[key] == nil or not RuleLab.in_run() then return end
    local state = RuleLab.ensure_state()
    state.config[key] = value == true
    if key == 'extra_action' then RuleLab.grant_extra_action() end
    if key == 'shop_echo' and not value then state.shop_echo = nil end
    if key == 'edition_amplifier' then
        for _, area in ipairs({G.jokers, G.consumeables}) do
            for _, card in ipairs(area.cards) do RuleLab.sync_negative(card) end
        end
    end
    -- Never reset used flags when toggling: once-per-blind/run remains once.
    -- Save only stable gameplay states, never an in-flight scoring animation.
    if G.STATE == G.STATES.SELECTING_HAND or G.STATE == G.STATES.SHOP
        or G.STATE == G.STATES.BLIND_SELECT then save_run() end
end

local groups = {
    {'经济商店', {'free_first_buy', 'sellback_plus', 'shop_echo'}},
    {'出牌牌组', {'extra_action', 'first_hand_echo', 'universal_rewrite'}},
    {'小丑版本', {'joker_overclock', 'vanilla_ascension', 'edition_amplifier'}},
    {'盲注连胜', {'blind_bailout', 'boss_reroll', 'no_discard_reward'}},
}
local hints = {
    free_first_buy = {'开启后，本商店首件购买免费。'},
    sellback_plus = {'开启后，每次出售小丑或消耗牌额外获得 $2。'},
    shop_echo = {'下次重掷保留上一商店第一格的小丑。'},
    extra_action = {'当前盲注立即补 1 次出牌和 1 次弃牌。', '每个盲注限补一次；关闭不扣除已补给次数。'},
    first_hand_echo = {'盲注首手得分乘 1.5；已出首手则下个盲注生效。'},
    universal_rewrite = {'盲注首手按同花顺结算；已出首手则下个盲注生效。'},
    joker_overclock = {'后续小丑触发使用超频；不重置已使用记录。'},
    vanilla_ascension = {'后续计分放大原版小丑的数值效果。'},
    edition_amplifier = {'后续计分放大版本效果；负片额外槽位立即更新。'},
    blind_bailout = {'下一次失败自动视为通过；每局仅一次。'},
    boss_reroll = {'在盲注选择界面提供一次免费重选。'},
    no_discard_reward = {'无弃牌通关后，下一回合增加出牌次数和现金。'},
}

local function text_row(text, scale, colour)
    return {n = G.UIT.R, config = {align = 'cm', padding = 0.035}, nodes = {
        {n = G.UIT.T, config = {text = text, scale = scale or 0.3,
            colour = colour or G.C.UI.TEXT_LIGHT, shadow = true}}
    }}
end

function RuleLab.panel_body(live)
    local target = live and RuleLab.ensure_state().config or mod.config
    local tabs = {}
    for i, group in ipairs(groups) do
        local keys = group[2]
        tabs[#tabs + 1] = {
            label = group[1], chosen = i == 1,
            tab_definition_function = function()
                local rows = {}
                for _, key in ipairs(keys) do
                    rows[#rows + 1] = create_toggle{
                        label = labels[key][1], ref_table = target, ref_value = key,
                        w = 3.2, label_scale = 0.4,
                        info = hints[key],
                        callback = function(value)
                            if live then RuleLab.set_live_rule(key, value)
                            else SMODS.save_mod_config(mod) end
                        end,
                    }
                end
                return {n = G.UIT.ROOT, config = {align = 'cm', colour = G.C.CLEAR}, nodes = {
                    {n = G.UIT.C, config = {align = 'cm', minw = 8, minh = 3.7}, nodes = rows}
                }}
            end,
        }
    end
    return {n = G.UIT.ROOT, config = {align = 'cm', colour = G.C.CLEAR}, nodes = {
        {n = G.UIT.C, config = {align = 'cm', padding = 0.05}, nodes = {
            text_row(live and '规则实验室 · 当前牌局' or '规则实验室 · 新局默认设置', 0.45, G.C.GOLD),
            text_row(live and '开关即时应用；已结算结果保留，限次奖励不会刷新。'
                or '对局中按 F8 或通过选项菜单随时更改。', 0.28),
            create_tabs{tabs = tabs, scale = 0.75, tab_h = 4.3, text_scale = 0.4},
        }}
    }}
end

mod.config_tab = function() return RuleLab.panel_body(RuleLab.in_run()) end

function RuleLab.open_runtime_panel(from_options)
    if not RuleLab.in_run() then return end
    if G.OVERLAY_MENU and not from_options then return end
    -- Do not interrupt evaluation; the normal pause/options path remains available.
    if not from_options and G.CONTROLLER and G.CONTROLLER.locked then return end
    G.SETTINGS.paused = true
    G.FUNCS.overlay_menu{definition = create_UIBox_generic_options{
        back_label = '返回牌局',
        contents = {{n = G.UIT.C, config = {align = 'cm'}, nodes = {RuleLab.panel_body(true)}}},
    }}
end

G.FUNCS.rule_lab_runtime_panel = function() RuleLab.open_runtime_panel(true) end
SMODS.Keybind{key = 'panel', key_pressed = 'f8', event = 'pressed',
    action = function() RuleLab.open_runtime_panel(false) end}
