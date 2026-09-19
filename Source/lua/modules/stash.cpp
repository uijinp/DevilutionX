#include "lua/modules/stash.hpp"

#include <algorithm>
#include <cstdint>
#include <limits>

#include <sol/sol.hpp>

#include "lua/metadoc.hpp"
#include "qol/stash.h"

namespace devilution {

sol::table LuaStashModule(sol::state_view &lua)
{
	sol::table table = lua.create_table();

	LuaSetDocFn(table, "getGold", "() -> integer",
	    "Gold currently held in the stash.",
	    []() -> int { return Stash.gold; });

	// Stash gold is a single int, not grid items, so its only limit is 32-bit overflow.
	// The in-game deposit paths guard the same way (qol/stash.cpp), so we saturate rather than wrap.
	LuaSetDocFn(table, "addGold", "(amount: integer) -> integer",
	    "Deposits gold straight into the stash, saturating at 2147483647. Returns the amount actually added.",
	    [](int amount) -> int {
		    if (amount <= 0)
			    return 0;
		    // 64비트로 계산한다. Stash.gold 가 어떤 이유로든 음수면 int 뺄셈이 오버플로한다.
		    const int64_t room = int64_t { std::numeric_limits<int>::max() } - std::max(Stash.gold, 0);
		    const int added = static_cast<int>(std::min<int64_t>(amount, room));
		    if (added <= 0)
			    return 0;
		    Stash.gold += added;
		    Stash.dirty = true; // without this the new balance is never written to the save
		    return added;
	    });

	return table;
}

} // namespace devilution
