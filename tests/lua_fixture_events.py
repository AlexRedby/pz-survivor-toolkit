"""Explicit event admission for offline fixture units, separate from barrier tests."""

OFFLINE_FIXTURE_EVENTS = """
package.preload.QueuePreflight=function()
 return {
  onGameStart=function(events,fn)events.OnGameStart.Add(fn)end,
  onTick=function(events,fn)events.OnTick.Add(fn)end,
  removeTick=function(events,fn)events.OnTick.Remove(fn)end
 }
end
"""
