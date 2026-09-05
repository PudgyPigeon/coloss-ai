defmodule WireWeb.StatusController do
  @moduledoc """
  Status controller offering basic health telemetry and standard system landing page.
  """

  use Phoenix.Controller, formats: [:html, :json]

  @spec health(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def health(conn, _params) do
    app_name = :wire |> to_string() |> String.upcase()
    version = :wire |> Application.spec(:vsn) |> to_string()

    json(conn, %{
      name: "THE " <> app_name,
      status: "ok",
      version: version,
      node: node(),
      connections: length(Node.list())
    })
  end

  @spec index(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def index(conn, _params) do
    app_name = :wire |> to_string() |> String.upcase()
    title = "THE " <> app_name

    html(conn, """
    <!DOCTYPE html>
    <html lang="en">
      <head>
        <title>#{title}</title>
        <link href="https://fonts.googleapis.com/css2?family=JetBrains+Mono:wght@400;700&display=swap" rel="stylesheet">
        <style>
          body {
            background-color: #030406;
            color: #00ff88;
            font-family: 'JetBrains Mono', monospace;
            margin: 0;
            padding: 40px;
            overflow: hidden;
            height: 100vh;
            box-sizing: border-box;
            display: flex;
            flex-direction: column;
            justify-content: center;
          }

          /* Scanline Effect */
          .scanlines {
            position: fixed;
            top: 0;
            left: 0;
            width: 100vw;
            height: 100vh;
            background: linear-gradient(
              to bottom,
              rgba(255, 255, 255, 0),
              rgba(255, 255, 255, 0) 50%,
              rgba(0, 0, 0, 0.2) 50%,
              rgba(0, 0, 0, 0.2)
            );
            background-size: 100% 4px;
            pointer-events: none;
            z-index: 100;
          }

          /* Subtle pulse on the text */
          .terminal-text {
            text-shadow: 0 0 5px rgba(0, 255, 136, 0.5);
            font-size: 1.2rem;
            line-height: 1.6;
            max-width: 800px;
            margin: 0 auto;
            width: 100%;
          }

          /* Typewriter line defaults to hidden */
          .line {
            opacity: 0;
            overflow: hidden;
            white-space: nowrap;
            width: 0;
            border-right: 2px solid transparent;
          }

          /* Typing animation */
          .type {
            animation: 
              typing 0.8s steps(40, end) forwards,
              blink-caret .75s step-end infinite;
          }

          /* Done typing state */
          .done {
            opacity: 1;
            width: 100%;
            border-right: none;
          }

          @keyframes typing {
            from { opacity: 1; width: 0 }
            to { opacity: 1; width: 100% }
          }
          @keyframes blink-caret {
            from, to { border-color: transparent }
            50% { border-color: #00ff88; }
          }

          /* The Action Button */
          .btn-container {
            margin-top: 40px;
            opacity: 0;
            transition: opacity 1s ease-in;
            text-align: center;
          }
          .btn-container.show {
            opacity: 1;
          }

          .enter-btn {
            display: inline-block;
            background: rgba(0, 255, 136, 0.1);
            color: #00ff88;
            text-decoration: none;
            padding: 12px 24px;
            border: 1px solid #00ff88;
            font-weight: 700;
            text-transform: uppercase;
            letter-spacing: 2px;
            box-shadow: 0 0 15px rgba(0, 255, 136, 0.2);
            transition: all 0.3s ease;
            cursor: pointer;
          }
          .enter-btn:hover {
            background: rgba(0, 255, 136, 0.2);
            box-shadow: 0 0 25px rgba(0, 255, 136, 0.5);
            text-shadow: 0 0 5px #00ff88;
          }
        </style>
      </head>
      <body>
        <div class="scanlines"></div>
        <div class="terminal-text" id="terminal">
          <div class="line">&gt; Initializing swarm protocols... [OK]</div>
          <div class="line">&gt; Establishing encrypted uplink... [OK]</div>
          <div class="line">&gt; Bypassing Don Erleone firewall... [OK]</div>
          <div class="line" style="color: #ffd700;">&gt; [ SYSTEM ONLINE ]</div>
          <div class="line">&gt; NODE: #{node()}</div>
          <div class="line">&gt; STATUS: Intercepting signals...</div>
          <div class="line">&gt; Agentic swarm ready for telemetry...</div>
        </div>

        <div class="btn-container" id="enter-action">
          <a href="/swarm" class="enter-btn">[ ENTER THE SWARM DECK ]</a>
        </div>

        <script>
          const lines = document.querySelectorAll('.line');
          let currentLine = 0;

          function typeNextLine() {
            if (currentLine < lines.length) {
              const line = lines[currentLine];
              line.classList.add('type');
              
              setTimeout(() => {
                line.classList.remove('type');
                line.classList.add('done');
                currentLine++;
                typeNextLine();
              }, 800);
            } else {
              setTimeout(() => {
                document.getElementById('enter-action').classList.add('show');
              }, 400);
            }
          }

          setTimeout(typeNextLine, 500);
        </script>
      </body>
    </html>
    """)
  end
end
