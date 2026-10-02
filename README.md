<p align="center">
  <img src="docs/assets/logo.svg" width="88" alt="Nextlet logo">
</p>

<h1 align="center">Nextlet</h1>

<p align="center">
  A personal task manager for <b>what's next</b>.<br>
  Tasks belong to a day, not an hour, and anything can move to tomorrow in one click.
</p>

<p align="center">
  <img src="docs/screenshots/web.png" alt="Nextlet in the browser: Today with a task's details open">
</p>

<table>
  <tr>
    <td><img src="docs/screenshots/mac-light.png" alt="The Mac app in light mode"></td>
    <td><img src="docs/screenshots/mac-dark.png" alt="The Mac app in dark mode"></td>
  </tr>
  <tr>
    <td align="center">Mac app</td>
    <td align="center">…and in dark mode</td>
  </tr>
</table>

## Quick start

1. **Start the server** (needs [Docker](https://docs.docker.com/get-docker/)):

   ```bash
   docker compose up -d                  # the server, for the Mac app
   docker compose --profile web up -d    # …plus the web app on http://localhost:8081
   ```

2. **Build and open the Mac app** (macOS 15+ with the Xcode Command Line Tools):

   ```bash
   cd mac && ./scripts/build-app.sh && open build/Nextlet.app
   ```

3. **Plan your day**
   - Press **+** or **⌘N** and type `Call mom tomorrow #Personal !2`: it sets the day, project and priority. Inside a project, new tasks land in that project.
   - Didn't get to something? **⌘→** (or **Tomorrow**) moves it to the next day.
   - On the Mac, **⌥Space** captures a task from any app.

Password protection, settings, shortcuts, starting at login, the API and development are in the [guide](docs/guide.md).
