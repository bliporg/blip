bundle = {}

---@function Shape creates a Shape, loading file from local app bundle.
---@param repoAndName string
---@return Shape
---@code
--- local bundle = require("bundle")
--- local shape = bundle.Shape("official.cubzh")
bundle.Shape = System.ShapeFromBundle

---@function MutableShape creates a MutableShape, loading file from local app bundle.
---@param repoAndName string
---@return MutableShape
---@code
--- local bundle = require("bundle")
--- local mutableShape = bundle.MutableShape("official.cubzh")
bundle.MutableShape = System.MutableShapeFromBundle

---@function Data reads a file from the local app bundle.
---@param filepath string
---@return Data
bundle.Data = System.DataFromBundle

return bundle
