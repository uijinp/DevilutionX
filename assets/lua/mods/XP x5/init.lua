-- XP x5 — 얻는 경험치를 5배로.
--
-- OnPlayerGainExperience 는 경험치가 더해지기 직전에 호출되지만 반환값으로 양을 바꿀 수는 없다.
-- 그래서 핸들러 안에서 (배율 - 1)배만큼을 한 번 더 준다. 그 호출이 다시 이 이벤트를 부르므로
-- 재진입 가드로 무한 반복을 막는다. 이벤트에 오는 값은 이미 레벨 차 보정과 멀티플레이 상한이
-- 적용된 값이라, 그대로 배율만 곱하면 된다.

local events = require("devilutionx.events")
local player = require("devilutionx.player")

local MULTIPLIER = 5
local in_bonus = false

events.OnPlayerGainExperience.add(function(_player, experience)
  if in_bonus or _player ~= player.self() or experience <= 0 then
    return
  end
  in_bonus = true
  local ok, err = pcall(function()
    _player:addExperience(experience * (MULTIPLIER - 1))
  end)
  in_bonus = false
  if not ok then
    error(err)
  end
end)
