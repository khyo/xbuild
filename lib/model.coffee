fs = require('fs-extra')
path = require('path')

module.exports =
  class Model
    # This model:
    #   handles loading project config and preferences JSONs
    #   provides project config and preferences to a controller
    #   reacts to live changes in the project config files: @onProjectChanged(...)
    #   saves preferences (if they've changed) on @close()
    constructor: (@onProjectChanged) ->
      @projects = {}
      @loadedProjectPaths = []
      @preferences = {}
      @master_preferences = null
      for projectPath in atom.project.getPaths()
        if @_readConfig(projectPath)
          @_readPreferences(projectPath)
          @loadedProjectPaths.push(projectPath)

    _readConfig: (projectPath) ->
      try
        configFile = fs.realpathSync(path.join(projectPath, '.xbuild.json'))
        readConfigAgain = @_readConfig.bind(this, projectPath)

        @projects[projectPath]?filewatcher?.close()
        @projects[projectPath]?filewatcher = undefined
        @projects[projectPath] = fs.readJsonSync(configFile)
        @projects[projectPath].filewatcher = fs.watch(
          configFile, {persistent: false}, (event, filename) -> readConfigAgain())
        @_compileProject(projectPath)
        @onProjectChanged?(projectPath, $projects[projectPath])
        return true
      catch
        console.log("Can't read .xbuild.json: #{projectPath}")
        return false
      @setActiveTarget("newTarget")

    _compileProject: (projectPath) ->
      proj = @projects[projectPath]
      proj.targets_by_name = {}
      d = proj.defaults
      compileTargets = (targets) ->
        for t in targets
          # Apply defaults in place of null fields
          for field in ["sh", "cwd", "build_cmd", "build_args", "debug_cmd",
            "debug_args", "exec_cmd", "exec_args", "error_match"]
            t[field] = t[field] or d[field]

          # Add name as build/exec/debug parameter if flag is set
          if ((t.pass_name_as_arg != false) and d.pass_name_as_arg) or (t.pass_name_as_arg == true)
            for field in ["build_args", "exec_args", "debug_args"]
              if t[field] then t[field].push(t.name) else t[field] = [t.name]

          # Add to the targets dictionary
          proj.targets_by_name[t.name] = t

          # recurse through the sub targets
          if t.targets?
            compileTargets(t.targets)
      compileTargets(proj.targets)

    _readPreferences: (projectPath) ->
      try
        prefFile = fs.realpathSync(path.join(projectPath, '.xbuild-preferences.json'))
        p = fs.readJsonSync(prefFile)
        @masterPreferences = p if not @masterPreferences
      catch
        console.log("Can't read .xbuild-preferences.json: " + projectPath)
        p = {}
      p._state =
        preferencesChanged: false
        path: prefFile
      @preferences[projectPath] = p

    _savePreferences: (projectPath) ->
      p = @preferences[projectPath]
      if p._state.preferencesChanged
        state = p._state
        try
          delete p._state
          fs.writeJsonSync(state.path, p)
          p._state = state
          p._state.preferencesChanged = false
          return true
        catch
          console.log("Can't save .xbuild-preferences.json: " + projectPath)
          return false

    dispose: () ->
      for projectname in @loadedProjectPaths when @projects[projectname]?
        @projects[projectname].filewatcher?.close()
        @_savePreferences(projectname)

    getProject: (projectpath) ->
      return @projects[projectpath]

    getTargets: (projectpath) ->
      return @projects[projectpath]?.targets_by_name

    # Model Interface API
    getTarget: (projectpath, targetname) ->
      if targetname.startsWith('#')
        targetname = @preferences[projectpath]?[targetname.slice(1)]
      return @projects[projectpath]?.targets_by_name[targetname]

    setPreference: (preference, value, projectpath) ->
      p = if not projectpath then @masterPreferences else @preferences[projectpath]
      if p?[preference] != value
        p[preference] = value
        p._state.preferencesChanged = true
        return true
      return false

    getPreference: (preference, projectpath) ->
      p = if not projectpath then @masterPreferences else @preferences[projectpath]
      return p?[preference]
