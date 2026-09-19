-- Novice Arsenal — 무기 종류별로 가장 damage 가 높은 무기를 1레벨부터 쓸 수 있게 지급한다.
--
-- 원작에서 무기 착용 조건은 캐릭터 레벨이 아니라 힘/마법/민첩 수치다(Player::CanUseItem).
-- 그래서 최고급 무기를 그냥 주면 저레벨에서는 못 드는 빨간 아이템이 된다.
-- 요구 능력치만 0 으로 바꾼 사본을 아이템 표에 추가해 지급한다. damage·내구도·그림·가격은 원본과 같다.
--
--   Novice Great Sword   10-20   (원본 Great Sword,  힘 75 필요)
--   Novice Great Axe     12-30   (원본 Great Axe,    힘 80 필요)
--   Novice Maul           6-20   (원본 Maul,         힘 55 필요)
--   Novice Long War Bow   1-14   (원본 Long War Bow, 힘 45 / 민첩 80 필요)
--   Novice War Staff      8-16   (원본 War Staff,    힘 30 필요)
--
-- addItem 이 아니라 addBaseItem 을 쓴다. addItem 은 접사를 굴리는데, 지팡이는 그 과정에서
-- 주문이 붙으면서 마법 요구치가 되살아나 다시 못 드는 아이템이 된다.

local events = require("devilutionx.events")
local items = require("devilutionx.items")
local player = require("devilutionx.player")

-- 기본 아이템 표가 0..167 을 쓰므로 멀리 떨어뜨려 잡는다. 다른 모드와 겹치면 게임이 종료된다.
local BASE_MAPPING_ID = 900000
local COUNT = 5

-- 아이템 표는 모드가 등록된 뒤에 읽히므로(LuaInitialize 가 LoadItemData 보다 먼저 돈다)
-- 이 이벤트는 반드시 잡힌다.
events.ItemDataLoaded.add(function()
  items.addItemDataFromTsv("txtdata\\items\\novice_arsenal.tsv", BASE_MAPPING_ID)
end)

-- 지급 기록. 다섯 자루는 모두 2x3 칸이라 인벤토리가 빈 상태여야 다 들어간다.
-- 전사는 시작 몽둥이가 한 열을 차지해 네 자루만 들어간다. 못 넣은 것은 기록하지 않으므로
-- 자리를 비우고 다시 들어오면 나머지를 받는다.
local given = {}

events.GameStart.add(function()
  local p = player.self()
  if p == nil then
    return
  end

  local mine = given[p.name]
  if mine == nil then
    mine = {}
    given[p.name] = mine
  end

  for n = 0, COUNT - 1 do
    local id = BASE_MAPPING_ID + n
    if not mine[id] then
      -- 인덱스는 다른 모드가 행을 추가하면 밀린다. 매핑 ID 로 찾는 편이 안전하다.
      local index = items.indexFromMappingId(id)
      if index >= 0 then
        if p:hasItem(index) then
          mine[id] = true               -- 이미 갖고 있다
        elseif p:addBaseItem(index, 1) then
          mine[id] = true               -- 이번에 지급했다
        end
        -- 자리가 없으면 기록하지 않는다 → 다음에 다시 시도한다
      end
    end
  end
end)
