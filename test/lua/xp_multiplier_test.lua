-- XP x10 모드의 배율·재진입 가드 검증. 엔진 없이 Lua 만으로 돈다.
--   docker run --rm -v "$PWD/assets/lua/mods/XP x10:/m:ro" \
--     -v "$PWD/test/lua/xp_multiplier_test.lua:/t/x.lua:ro" nickblah/lua:5.4 lua /t/x.lua
-- 배율을 바꾸면 아래 기대값도 함께 고칠 것.
-- 엔진 대역. addExperience 가 다시 OnPlayerGainExperience 를 부르는 실제 동작까지 흉내 내
-- 재진입 가드와 배율을 함께 검증한다.
local granted, handlers = 0, {}
local events = { OnPlayerGainExperience = { add = function(f) handlers[#handlers + 1] = f end } }
local me
local function fire(p, xp)
  granted = granted + xp
  for _, f in ipairs(handlers) do f(p, xp) end
end
me = { addExperience = function(self, xp) fire(self, xp) end }
local playerMod = { self = function() return me end }

local realRequire = require
require = function(n)
  if n == "devilutionx.events" then return events end
  if n == "devilutionx.player" then return playerMod end
  return realRequire(n)
end

dofile("/m/init.lua")
assert(#handlers == 1, "핸들러가 등록되지 않았다")

fire(me, 100)                       -- 몬스터가 100 경험치를 준 상황
print(string.format("base 100 -> granted %d", granted))
assert(granted == 1000, "10배가 아니다: " .. granted)

granted = 0
fire(me, 37)
print(string.format("base 37  -> granted %d", granted))
assert(granted == 370, "10배가 아니다: " .. granted)

granted = 0
fire(me, 0)                         -- 0 은 보너스를 주지 않아야 한다
assert(granted == 0, "0 경험치에 보너스가 붙었다: " .. granted)
print("OK: 10배, 재진입 가드 정상, 0 경험치 안전")
