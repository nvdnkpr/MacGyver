angular.module("Mac").factory "TableBaseColumn", [ ->
  class TableBaseColumn
]

angular.module("Mac").factory "TableSectionController", [ ->
  class TableSectionController
    constructor: (@section) ->
    # Value should probably be overridden by the user
    cellValue: (row, colName) -> @defaultCellValue(row, colName)
    # Since accessing a models key is useful
    # we keep this as a separate method
    defaultCellValue: (row, colName) -> row.model[colName]
]

# For legacy support only
angular.module("Mac").factory "SectionController", [
  "TableSectionController"
  (TableSectionController) -> TableSectionController
]

angular.module("Mac").factory "TableRow", [ ->
  class TableRow
    constructor: (@section, @model, @cells = [], @cellsMap = {}) ->

    toJSON: ->
      cells: @cells
]

angular.module("Mac").factory "TableSection", [ ->
  class TableSection
    constructor: (controller, @table, @name, @rows = []) ->
      @setController controller

    setController: (controller) ->
      @ctrl = new controller(this)

    toJSON: ->
      rows: @rows
]

angular.module("Mac").factory "tableComponents", [
  "TableSectionController"
  "TableRow"
  "TableSection"
  (
    TableSectionController
    TableRow
    TableSection
  ) ->
    rowFactory: (section, model) ->
      return new TableRow(section, model)

    columnFactory: (colName, proto = {}) ->
      Column           = (@colName) ->
      Column.prototype = proto
      return new Column(colName)

    sectionFactory: (table, sectionName, controller = TableSectionController) ->
      return new TableSection(controller, table, sectionName)

    cellFactory: (row, proto = {}) ->
      Cell = (@row, @column) ->
        # TODO: Find a better place for this, we can't use our prototype though...
        @value = -> @row?.section?.ctrl.cellValue(@row, @colName)
        # Allow for custom functions on the controller
        @get   = (name) -> @row?.section?.ctrl[name]?(@row, @colName)
        @toJSON = ->
          value: @value()
          column: @column.colName
        return
      Cell.prototype = proto
      return new Cell(row, proto)
]

angular.module("Mac").factory "dynamicColumnsFunction", ->
  (models) ->
    first   = models[0]
    columns = (key for key, model of first)
    @set(columns)

angular.module("Mac").factory "TableColumnsController", [
  "tableComponents"
  "dynamicColumnsFunction"
  (
    tableComponents
    dynamicColumnsFunction
  ) ->
    class ColumnsController
      constructor: (@table) ->

      # Our overridable dynamic columns function
      dynamic: dynamicColumnsFunction

      blank: ->
        # Makes a blank object with our colNames as keys
        obj = {}
        for colName in @table.columnsOrder
          obj[colName] = null
        obj

      reset: ->
        @table.columnsOrder = []
        @table.columns      = []
        @table.columnsMap   = {}

      set: (columns) ->
        @reset()
        # Store the order
        @table.columnsOrder = columns
        for colName in columns
          column = tableComponents.columnFactory(colName, @table.baseColumn)
          @table.columnsMap[colName] = column
          @table.columns.push column

      syncOrder: ->
        # Function might be better in table...
        for sectionName, section of @table.sections
          for row in section.rows
            cells = []
            for colName in @table.columnsOrder
              cells.push row.cellsMap[colName]
            row.cells = cells
        columns = []
        for colName in @table.columnsOrder
          columns.push @table.columnsMap[colName]
        @table.columns = columns
]

angular.module("Mac").factory "TableRowsController", [
    "tableComponents"
    (
        tableComponents
    ) ->
      class RowsController
        constructor: (@table) ->

        make: (section, model) ->
          row = tableComponents.rowFactory(section, model)
          for colName, column of @table.columnsMap
            cell = tableComponents.cellFactory(row, column)
            row.cellsMap[colName] = cell
            row.cells.push cell
          row

        set: (sectionName, models, sectionController) ->
          @table.sections[sectionName] = section =
            tableComponents.sectionFactory(
                @table, sectionName, sectionController)

          # Don't continue if no models
          return unless models?.length?

          if @table.dynamicColumns
            @table.columnsCtrl.dynamic(models)

          rows = []
          for model in models
            rows.push @make(section, model)

          section.rows = rows
          @table.columnsCtrl.syncOrder()

        insert: (sectionName, model, index) ->
          section = @table.sections[sectionName]
          row     = @make section, model
          section.rows.splice(index, 0, row)

        remove: (sectionName, index) ->
          section = @table.sections[sectionName]
          return section.rows.splice(index, 1)
]

angular.module("Mac").factory "Table", [
    "TableBaseColumn"
    "TableColumnsController"
    "TableRowsController"
    (
        TableBaseColumn
        TableColumnsController
        TableRowsController
    ) ->
      # Helper functions
      convertObjectModelsToArray = (models) ->
        if models and not angular.isArray models then [models] else models

      # The Table class
      class Table
        constructor: (columns = [], @baseColumn = new TableBaseColumn()) ->
          @sections       = {}
          @columns        = []
          @columnsCtrl    = new TableColumnsController(this)
          @rowsCtrl       = new TableRowsController(this)
          @dynamicColumns = columns is 'dynamic'
          if not @dynamicColumns
            @columnsCtrl.set(columns)
          return

        load: (sectionName, models, sectionController) ->
          models = convertObjectModelsToArray models

          # Check if we're working with an existing section, if so we want to
          # intelligently insert / remove only what we need to
          if @sections[sectionName]?.rows.length
            tableModels  = []
            toBeRemoved  = []
            toBeInserted = []

            # Find which items need to be removed
            for row, index in @sections[sectionName].rows
              if row.model not in models
                toBeRemoved.push [sectionName, index]
              else
                tableModels.push row.model

            # We do this in reverse order to avoid changing the positions of the
            # items as we remove them
            toBeRemoved.reverse()
            @remove.apply this, args for args in toBeRemoved

            for model, index in models when model not in tableModels
                toBeInserted.push [sectionName, model, index]

            @insert.apply this, args for args in toBeInserted

            # If we're passed a section controller, set it for this section
            if sectionController
              @sections[sectionName].setController sectionController

          # New or empty section, load using set which will also create a section
          else
            @rowsCtrl.set sectionName, models, sectionController

        insert: (sectionName, model, index = 0) ->
          @rowsCtrl.insert sectionName, model, index

        remove: (sectionName, index = 0) ->
          @rowsCtrl.remove sectionName, index

        blankRow: ->
          @columnsCtrl.blank()

        toJSON: ->
          sections: @sections
]