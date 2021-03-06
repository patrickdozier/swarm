'use strict'

###*
 # @ngdoc function
 # @name swarmApp.controller:LoadsaveCtrl
 # @description
 # # LoadsaveCtrl
 # Controller of the swarmApp
 #
 # Loads a saved game upon refresh. If it fails, complain loudly and give the player a chance to recover their broken save.
###
angular.module('swarmApp').controller 'LoadSaveCtrl', ($scope, $log, game, session, version, $location, backfill, linkPublicTest1, isKongregate, storage, saveId) ->
  $scope.form = {}
  $scope.isKongregate = isKongregate

  # http://stackoverflow.com/questions/14995884/select-text-on-input-focus-in-angular-js
  $scope.select = ($event) ->
    $event.target.select()

  $scope.contactUrl = ->
    "#/contact?#{$.param error:$scope.form.error}"

  try
    exportedsave = session.getStoredSaveData()
  catch e
    $log.error "couldn't even read localstorage! oh no!", e
    game.reset true
    # show a noisy freakout message at the top of the screen with the exported save
    $scope.form.errored = true
    $scope.form.error = e.message
    $scope.form.domain = window.location.host
    # tell analytics
    $scope.$emit 'loadGameFromStorageFailed', e.message
    return

  try
    session.load()
    $log.debug 'Game data loaded successfully.', this
  catch e
    # Couldn't load the user's saved data. 
    if not exportedsave
      # If this is their first visit to the site, that's normal, no problems
      $log.debug "Empty saved data; probably the user's first visit here. Resetting quietly."
      game.reset true #but don't save, in case we're waiting for flash recovery
      # listen for flash to load - loading it takes extra time, but we might find a save there.
      storage.flash.onReady.then =>
        encoded = storage.flash.getItem saveId
        if encoded
          $log.debug "flash loaded successfully, and found a saved game there that wasn't in cookies/localstorage! importing."
          # recovered save from flash! tell analytics
          $scope.$emit 'savedGameRecoveredFromFlash', e.message
          game.importSave encoded, true # don't save when recovering from flash - if this is somehow a mistake, player can take no action
        else
          $log.debug 'flash loaded successfully, but no saved game found. this is truly a new visitor.'
    else
      # Couldn't load an actual real save. Shit.
      $log.warn "Failed to load non-empty saved data! Oh no!"
      # reset, but don't save after resetting. Try to keep the bad data around unless the player takes an action.
      game.reset true
      # show a noisy freakout message at the top of the screen with the exported save
      $scope.form.errored = true
      $scope.form.error = e.message
      $scope.form.export = exportedsave
      # tell analytics
      $scope.$emit 'loadGameFromStorageFailed', e.message

  # try to load a save file from the url.
  if (savedata = $location.search().savedata)?
    $log.info 'loading game from url...'
    # transient=true: don't overwrite the saved data until we buy something
    game.importSave savedata, true
    $log.info 'loading game from url successful!'

  backfill.run game
  try
    linkPublicTest1 $scope
  catch e
    # pass
    console.error e

angular.module('swarmApp').controller 'WelcomeBackCtrl', ($scope, $log, $interval, game) ->
  # Show the welcome-back screen only if we've been gone for a while, ie. not when refreshing.
  # Do all time-checks for the welcome-back screen *before* scheduling heartbeats/onclose.
  $scope.durationSinceClosed = game.session.durationSinceClosed()
  $scope.showWelcomeBack = $scope.durationSinceClosed.asMinutes() >= 3
  #$scope.showWelcomeBack = true # uncomment for testing!
  reifiedToCloseDiffInSecs = (game.session.dateClosed().getTime() - game.session.date.reified.getTime()) / 1000
  $log.debug 'time since game closed', $scope.durationSinceClosed.humanize(),
    millis:game.session.millisSinceClosed()
    reifiedToCloseDiffInSecs:reifiedToCloseDiffInSecs

  # Store when the game was closed. Try to use the browser's onclose (onunload); that's most precise.
  # It's unreliable though (crashes fail, cross-browser's icky, ...) so use a heartbeat too.
  # Wait until showWelcomeBack is set before doing these, or it'll never show
  $(window).unload -> game.session.onClose()
  $interval (-> game.session.onHeartbeat()), 60000
  game.session.onHeartbeat() # game.session time checks after this point will be wrong

  if not $scope.showWelcomeBack
    return

  $scope.closeWelcomeBack = ->
    $log.debug 'closeWelcomeBack'
    $('#welcomeback').alert('close')
    return undefined #quiets an angular error

  # show all tab-leading units, and three leading generations of meat
  interestingUnits = []
  leaders = 0
  for unit in game.tabs.byName.meat.sortedUnits
    if leaders >= 3
      break
    if !unit.velocity().isZero()
      leaders += 1
      interestingUnits.push unit
  interestingUnits = interestingUnits.concat _.map game.tabs.list, 'leadunit'
  uniq = {}
  $scope.offlineGains = _.map interestingUnits, (unit) ->
    if not uniq[unit.name]
      uniq[unit.name] = true
      countNow = unit.count()
      countClosed = unit._countInSecsFromReified reifiedToCloseDiffInSecs
      countDiff = countNow.minus countClosed
      if countDiff.greaterThan 0
        return unit:unit, val:countDiff
  $scope.offlineGains = (g for g in $scope.offlineGains when g)

angular.module('swarmApp').factory 'linkPublicTest1', ($log, $location, game, kongregate) -> return ($scope) ->
  #console.log LZString.compressToBase64 JSON.stringify date:new Date()

  encoded = $location.search().publictest
  if encoded
    args = JSON.parse LZString.decompressFromBase64 encoded
    datediff = Math.abs new Date().getTime() - new Date(args.date ? 0).getTime()
    if datediff < 5 * 60 * 1000
      $scope.$emit 'achieve-publictest1'
      $log.debug 'linkPublicTest1: achieve-publictest1', datediff
      $location.search 'publictest', null
