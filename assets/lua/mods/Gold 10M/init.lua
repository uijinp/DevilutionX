-- Gold 10M — 캐릭터의 총 소지금(인벤토리 + 금고)을 1,000만으로 맞춰 준다.
--
-- 엔진에서 인벤토리의 골드는 "골드 더미 아이템"이다. 한 칸에 MaxGold(기본 5000, 금빛 부적을
-- 끼면 10000)까지만 담기고 칸은 40개뿐이라, 들고 다닐 수 있는 최대치는 20만이다.
-- 1,000만을 인벤토리에 밀어 넣으면 40칸이 전부 골드로 차서 전리품을 주울 자리가 없어진다.
-- 그래서 지갑 몫만 인벤토리에 두고 나머지는 금고에 넣는다.
-- 금고 골드는 아이템이 아니라 정수 하나라서 21억까지 들어가고 세이브에도 남는다.
--
-- Player.gold / Player:addGold / devilutionx.stash 는 이 포크에서 추가한 바인딩이다.

local events = require("devilutionx.events")
local player = require("devilutionx.player")
local stash = require("devilutionx.stash")
local message = require("devilutionx.message")

local TARGET = 10000000 -- 인벤토리 + 금고 합계
local WALLET = 25000    -- 인벤토리에 유지할 금액. 5칸이면 상점은 충분하다.

events.GameStart.add(function()
  local p = player.self()
  if p == nil then
    return
  end

  -- 1) 지갑 채우기. 쓴 만큼 다시 채워지므로 상점에서 돈이 마르지 않는다.
  local short = WALLET - p.gold
  if short > 0 then
    local leftover = p:addGold(short)
    if leftover > 0 then
      stash.addGold(leftover) -- 인벤토리가 꽉 찼으면 금고로 돌린다
    end
  end

  -- 2) 합계를 TARGET 으로 맞추기. 모자란 만큼만 넣으므로 다시 들어와도 불어나지 않는다.
  --    모드 상태를 세이브에 남길 방법이 없어, 실제 소지액을 기준으로 삼는다.
  local missing = TARGET - (p.gold + stash.getGold())
  if missing > 0 then
    stash.addGold(missing)
  end

  -- 금고는 마을에서 열어 꺼내 쓴다. 어디에 얼마가 있는지 한 줄로 알려 준다.
  -- (ASCII 로만 쓴다. 게임 언어에 따라 글꼴이 달라도 깨지지 않는다.)
  message(string.format("Gold 10M: %d carried, %d in stash", p.gold, stash.getGold()))
end)
