_ = require('lodash')
fs = require('fs-extra')
{CompositeDisposable} = require('atom')
child_process = require('child_process')

views = require('./views')
views.SaveConfirmView = require('./save-confirm-view')  # using old save-confirm
ErrorMatcher = require('./error-matcher')


module.exports =
  class Controller
    constructor: (@model) ->
      @subscriptions = new CompositeDisposable

      # Wire up the model
      @subscriptions.add @model
      @model.onProjectChanged = @modelChangedHandler
      @modelChangedHandler()

      # Prepare the build child process
      @child = null

      # Create the buildview and couple it with the errorMatcher
      @buildView = new views.BuildView()
      @errorMatcher = new ErrorMatcher()
      @errorMatcher.on('error', (message) ->
        atom.notifications.addError('Error matching failed!', {detail: message}))
      @errorMatcher.on('scroll', @buildView.scrollTo.bind(@buildView))
      @errorMatcher.on('replace', @buildView.replace.bind(@buildView))

      # Listen in on texteditor save events if we want to build on each save
      # saveOnBuildIfConfigured = ->
      #   if atom.config.get('build:buildOnSave') then @build('save')
      # saveOnBuildIfConfigured = saveOnBuildIfConfigured.bind(this)
      # atom.workspace.observeTextEditors((editor) ->
      #   editor.onDidSave(() -> saveOnBuildIfConfigured())

    dispose: ->
      @subscriptions.dispose()
      if @child then kill(@child.pid, 'SIGKILL')
      if @finishedTimer then clearTimeout(@finishedTimer)

    modelChangedHandler: (projectPath, project) ->
      @activeProject = @getActiveProject()
      @updateStatusBar()

    getActiveProject: ->
      projectPaths = atom.project.getPaths()

      # look for a stored active_project path if available
      preferred_project = @model.getPreference('active_project')
      if preferred_project?
        foundPath = _.find(projectPaths, (path) -> preferred_project == path)
        return foundPath if foundPath

      # use an editorpath if one is available
      editorPath = atom.workspace.getActiveTextEditor()?.getPath()
      if editorPath?
        foundPath = _.find(projectPaths, (path) -> editorPath.startsWith(fs.realpathSync(path)))
        return foundPath if foundPath

      # Default to first projectPath, or return empty path
      return if projectPaths.length > 0 then projectPaths[0] else ''

    getTarget: (targetname="#target_default") ->
      @model.getTarget(@activeProject, targetname)

    setActiveTarget: (targetname) ->
      if targetname
        @model.setPreference("target_active", targetname, @activeProject)
        @updateStatusBar()

    consumeStatusBar: (statusBar) ->
      # Wire up a status view
      @statusView = new views.StatusView()
      @statusView.onClick(@selectActiveProjectDialog.bind(this),
        @selectActiveTargetDialog.bind(this))
      @updateStatusBar()
      @subscriptions.add statusBar.addRightTile(item: @statusView, priority:300)

    updateStatusBar: ->
      @statusView?.update(@activeProject.split('/').slice(-1), @getTarget("#target_active")?.name)

    setActiveProject: (projectPath) ->
      @activeProject = projectPath
      @model.setPreference('active_project', projectPath)  # set on master_preferences
      @statusView.update(@activeProject.split('/').slice(-1), @getTarget("#target_active")?.name)
      @updateStatusBar()

    selectActiveProjectDialog: ->
      spv = new views.SelectionView(@model.loadedProjectPaths, @activeProject
        @setActiveProject.bind(this), "Select Active Project")

    selectActiveTargetDialog: ->
      spv = new views.SelectionView(key for key of @model.getTargets(@activeProject),
        @getTarget("#target_active").name, @setActiveTarget.bind(this), "Select Active Target")

    toggleBuildPane: ->
      @buildView.toggle()

    startBuild: (target, verb) ->
      t = target
      # extract cmd and args based on the requested verb
      cmd = t[verb+"_cmd"]
      args = t[verb+"_args"]

      # if t.sh  # reformat cmd and args for shell if necessary
      #   args = ['-c ' + [cmd].concat(args).join(' ')]
      #   cmd = '/bin/sh'

      errorMatcher = @errorMatcher
      buildView = @buildView
      finishedTimer = @finishedTimer

      @child = child_process.spawn(cmd, args, {cwd: t.cwd})
      @child.stdout.on('data', (data) ->
        buildView.append(data))

      @child.stderr.on('data', (data) ->
        buildView.append(data))

      @child.on('error', (err) ->
        buildView.append("Failed executing cmd: " + cmd + " with args: " + args + '\n'))

      @child.on('close', (exitCode) ->
        buildView.buildFinished(exitCode == 0)
        errorMatcher.set(t.error_match, t.cwd, buildView.output.text())
        if exitCode != 0 and atom.config.get('build.scrollOnError')
            errorMatcher.matchFirst()
        @child = null
      )

      @buildView.buildStarted()
      @buildView.append("Executing cmd: " + cmd + " with args: " + args + '\n')

    buildTarget: (targetname="#target_default", verb="build") ->
      t = @getTarget(targetname)
      if t
        @startBuild(t, verb)
