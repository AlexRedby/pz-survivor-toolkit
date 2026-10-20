"""Relative wall route releases real steering once, even after collision feedback."""
from pathlib import Path
import json
import shutil
import subprocess
import unittest

ROOT=Path(__file__).resolve().parents[1]
LUA=shutil.which('luajit') or shutil.which('lua')

@unittest.skipUnless(LUA, 'Lua runtime required')
class WallInput(unittest.TestCase):
    def test_mirrored_turn_release_and_no_automatic_reverse(self):
        source=ROOT/'tests/native_queue/contributions/wooden_cart_multiplayer/wall-input.lua'
        code='local M=dofile('+json.dumps(str(source))+')\n'+r"""
        for _,side in ipairs({'left','right'}) do
          local sign=side=='left' and 1 or -1
          local steps=M.steps(side); local released={}
          assert(#steps==8 and steps[1][1]==0 and steps[8][1]==26000)
          for i,step in ipairs(steps) do
            if i==4 or i==6 or i==7 then
              local reverse=i==4
              local target=sign*(reverse and math.pi*.75 or i==6 and math.pi*.25 or 0)
              local direction=sign*(reverse and 1 or -1)
              assert(M.drive(side,step,released,target-direction*.3)==step[2])
              assert(M.drive(side,step,released,target-direction*.01)==(reverse and 4 or 1))
              -- Collision feedback cannot re-press released steering.
              assert(M.drive(side,step,released,target-direction*.5)==(reverse and 4 or 1))
            else
              assert(M.drive(side,step,released,0)==step[2])
            end
          end
          assert(steps[2][2]==1 and steps[3][2]==4 and steps[5][2]==0 and steps[8][2]==0)
        end
        local front=M.steps('front')
        local expected={{0,0},{1000,1},{6500,0},{7500,4},{10000,0},{10800,1},{15500,0}}
        assert(#front==#expected)
        for i,step in ipairs(front) do
          assert(step[1]==expected[i][1] and step[2]==expected[i][2] and step[3]==0)
          for _,heading in ipairs({0,math.pi/2,math.pi}) do assert(M.drive('front',step,{},heading)==step[2]) end
        end
        assert(not pcall(M.steps,'invalid'))
        """
        subprocess.run([LUA,'-e',code],check=True,capture_output=True,text=True)

if __name__=='__main__': unittest.main()
