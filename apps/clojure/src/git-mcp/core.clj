(ns git-mcp.core)

(defn read-git-file [path]
  (str "reading file at: " path))

(defn -main [& args]
  (println (read-git-file "flake.nix")))

(-main)