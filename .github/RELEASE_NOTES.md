The includes are now named **IPL.lua** and **IDE.lua**.

```lua
local IPL = require("IPL")
```

Update existing lowercase imports when upgrading. `IPL.registerIDE` loads
`IDE.lua` automatically. Direct IDE imports use `require("IDE")`.
Examples, documentation and checks use the exact filename case on Linux.

Loading behavior is unchanged. Addon-Sscanf remains required.
