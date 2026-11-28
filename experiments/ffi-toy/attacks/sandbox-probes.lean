-- Appended to the honest Solution.lean by attacks.sh: #eval probes that run during the build.
def tryIt (what : String) (act : IO Unit) : IO Unit := do
  try act; IO.println s!"PROBE {what}: SUCCEEDED" catch e => IO.println s!"PROBE {what}: blocked ({e})"

#eval tryIt "write home" (do IO.FS.writeFile ((← IO.getEnv "HOME").getD "" ++ "/PWNED_comparator_test") "x")
#eval tryIt "write project source" (IO.FS.writeFile "Challenge.lean" "-- tampered")
#eval tryIt "read home" (do let _ ← IO.FS.readFile ((← IO.getEnv "HOME").getD "" ++ "/.bashrc"); pure ())
#eval tryIt "network" (do let o ← IO.Process.output {cmd := "curl", args := #["-sS", "-m", "5", "https://example.com"]}; if o.exitCode != 0 then throw (IO.userError o.stderr))
