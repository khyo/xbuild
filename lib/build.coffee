child_process = require('child_process')
_ = require('lodash')
{Disposable, CompositeDisposable} = require('atom')
kill = require('tree-kill')

Model = require('./model')
Controller = require('./controller')

# SaveConfirmView = require('./save-confirm-view')
# TargetsView = require('./targets-view')
# BuildView = require('./build-view')
# ErrorMatcher = require('./error-matcher')
# tools = require('./tools')
# extra_tools = []

class BuildError extends Error
  @content: (@name, @message) ->
    @captureStackTrace(BuildError)

module.exports =
  config:
    panelVisibility:
      title: 'Panel Visibility'
      description: 'Set when the build panel should be visible.'
      type: 'string'
      default: 'Toggle'
      enum: [ 'Toggle', 'Keep Visible', 'Show on Error', 'Hidden' ]
      order: 1
    buildOnSave:
      title: 'Automatically build on save'
      description: 'Autmatically build your project each time an editor is saved.'
      type: 'boolean'
      default: false
      order: 2
    saveOnBuild:
      title: 'Automatically save on build'
      description: 'Automatically save all edited files when triggering a build.'
      type: 'boolean'
      default: false
      order: 3
    scrollOnError:
      title: 'Automatically scroll on build error'
      description: 'Automatically scroll to first matched error when a build failed.'
      type: 'boolean'
      default: false
      order: 4
    stealFocus:
      title: 'Steal Focus'
      description: 'Steal focus when opening build panel.'
      type: 'boolean'
      default: true
      order: 5
    monocleHeight:
      title: 'Monocle Height'
      description: 'How much of the workspace to use for build panel when it is "maximized".'
      type: 'number'
      default: 0.75
      minimum: 0.1
      maximum: 0.9
      order: 6
    minimizedHeight:
      title: 'Minimized Height'
      description: 'How much of the workspace to use for build panel when it is "minimized".'
      type: 'number'
      default: 0.15
      minimum: 0.1
      maximum: 0.9
      order: 7

  activate: (state) ->
    @subscriptions = new CompositeDisposable
    @controller = new Controller(new Model())
    @subscriptions.add @controller

    # Commands
    @subscriptions.add atom.commands.add 'atom-workspace', 'xbuild:target': (event) =>
      @controller.buildTarget(event.detail)
    @subscriptions.add atom.commands.add 'atom-workspace', 'xbuild:test': =>
      @controller.buildTarget("#target_test")
    @subscriptions.add atom.commands.add 'atom-workspace', 'xbuild:clean': =>
      @controller.buildTarget("#target_clean")
    @subscriptions.add atom.commands.add 'atom-workspace', 'xbuild:active': =>
      @controller.buildTarget("#target_active")
    @subscriptions.add atom.commands.add 'atom-workspace', 'xbuild:set-active': (event) =>
      @controller.setActiveTarget(event.detail)
    @subscriptions.add atom.commands.add 'atom-workspace', 'xbuild:exec-active': =>
      @controller.buildTarget("#target_active", "exec")
    @subscriptions.add atom.commands.add 'atom-workspace', 'xbuild:select-project': =>
      @controller.selectActiveProjectDialog()
    @subscriptions.add atom.commands.add 'atom-workspace', 'xbuild:select-target': =>
      @controller.selectActiveTargetDialog()
    @subscriptions.add atom.commands.add 'atom-workspace', 'xbuild:toggle': =>
      @controller.toggleBuildPane()

  deactivate: ->
    @subscriptions.dispose()
    # @buildView.destroy()
    # # from old file
    # @customFileWatcher?.close()
    # if @child?
    #   kill(@child.pid, 'SIGKILL')
    # clearTimeout(@finishedTimer)

  consumeStatusBar: (statusBar) ->
    @controller.consumeStatusBar(statusBar)

  provideDebugTargetGetter: ->
    return @controller.getTarget.bind(@controller, "#target_active")
