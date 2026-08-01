_:

{
  home.file = {
    ".jupyter/jupyter_server_config.py" = {
      force = true;
      text = ''
        c.ServerApp.open_browser = True
      '';
    };

    ".jupyter/lab/user-settings/@jupyterlab/apputils-extension/themes.jupyterlab-settings" = {
      force = true;
      text = builtins.toJSON {
        theme = "JupyterLab Dark";
      };
    };

    ".jupyter/lab/user-settings/@jupyterlab/lsp-extension/plugin.jupyterlab-settings" = {
      force = true;
      text = builtins.toJSON {
        activate = "on";
      };
    };

    ".jupyter/lab/user-settings/@jupyterlab/completer-extension/manager.jupyterlab-settings" = {
      force = true;
      text = builtins.toJSON {
        autoCompletion = true;
      };
    };

    ".jupyter/lab/user-settings/@jupyter-lsp/jupyterlab-lsp/completion.jupyterlab-settings" = {
      force = true;
      text = builtins.toJSON {
        continuousHinting = true;
      };
    };
  };
}
