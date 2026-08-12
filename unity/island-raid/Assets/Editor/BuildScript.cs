// CI 建置腳本（GameCI buildMethod 進入點）
// 程式化生成場景與調色盤材質，設定 WebGL gzip 壓縮後建置
using System;
using System.IO;
using UnityEditor;
using UnityEditor.Build.Reporting;
using UnityEditor.SceneManagement;
using UnityEngine;

namespace IslandRaid.EditorTools {

public static class BuildScript {
    public static void BuildWebGL() {
        string path = "build/WebGL";
        var args = Environment.GetCommandLineArgs();
        for (int i = 0; i < args.Length - 1; i++)
            if (args[i] == "-customBuildPath") path = args[i + 1];

        PlayerSettings.companyName = "chimerakang";
        PlayerSettings.productName = "IslandRaidV2";
        PlayerSettings.runInBackground = true;
        // GitHub Pages 無法自訂 Content-Encoding 標頭 → gzip + 解壓縮備援
        PlayerSettings.WebGL.compressionFormat = WebGLCompressionFormat.Gzip;
        PlayerSettings.WebGL.decompressionFallback = true;
        PlayerSettings.WebGL.dataCaching = true;

        // 生成場景：只放調色盤（材質資產保證進包，避免 WebGL shader 被剝除變粉紅）
        var scene = EditorSceneManager.NewScene(NewSceneSetup.EmptyScene, NewSceneMode.Single);
        var pgo = new GameObject("Palette");
        var pal = pgo.AddComponent<IslandRaid.Palette>();
        var names = IslandRaid.MatLib.DefNames;
        var cols = IslandRaid.MatLib.DefColors;
        Directory.CreateDirectory("Assets/PaletteMats");
        var mats = new Material[names.Length];
        for (int i = 0; i < names.Length; i++) {
            var m = new Material(Shader.Find("Standard"));
            m.color = cols[i];
            m.SetFloat("_Glossiness", 0f);
            AssetDatabase.CreateAsset(m, "Assets/PaletteMats/" + names[i] + ".mat");
            mats[i] = m;
        }
        pal.names = names;
        pal.materials = mats;
        Directory.CreateDirectory("Assets/Scenes");
        EditorSceneManager.SaveScene(scene, "Assets/Scenes/Main.unity");
        AssetDatabase.SaveAssets();

        var opts = new BuildPlayerOptions {
            scenes = new[] { "Assets/Scenes/Main.unity" },
            locationPathName = path,
            target = BuildTarget.WebGL,
            options = BuildOptions.None,
        };
        var report = BuildPipeline.BuildPlayer(opts);
        Debug.Log("Build result: " + report.summary.result + ", output: " + path);
        if (report.summary.result != BuildResult.Succeeded)
            EditorApplication.Exit(1);
    }
}

}
