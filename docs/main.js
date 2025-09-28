// Load and display builds from builds.json
async function loadBuilds() {
    const buildsContainer = document.getElementById('builds-list');
    
    try {
        const response = await fetch('builds/builds.json');
        if (!response.ok) {
            throw new Error(`HTTP ${response.status}: ${response.statusText}`);
        }
        
        const builds = await response.json();
        
        if (builds.length === 0) {
            buildsContainer.innerHTML = '<div class="error">No builds available yet.</div>';
            return;
        }
        
        // Generate HTML for each build
        const buildsHtml = builds.map(build => {
            // Compute install URL dynamically from plist_url
            // Properly encode the manifest URL for itms-services protocol
            const encodedManifestUrl = encodeURIComponent(build.plist_url);
            const installUrl = `itms-services://?action=download-manifest&url=${encodedManifestUrl}`;

            console.log(`plist URL: ${build.plist_url}`);
            console.log(`Computed install URL: ${installUrl}`);
            return `
                <div class="build-item">
                    <div class="build-info">
                        <div class="build-version">v${build.version} (${build.build})</div>
                        <div class="build-meta">
                            Built: ${build.date}<br>
                            File: ${build.filename}.ipa
                        </div>
                    </div>
                    <a href="${installUrl}" class="install-btn">Install</a>
                </div>
            `;
        }).join('');
        
        buildsContainer.innerHTML = buildsHtml;
        // log the actual value of the install URL for debugging by querying the DOM
        const firstInstallBtn = document.querySelector('.install-btn');
        if (firstInstallBtn) {
            console.log(`First install button href: ${firstInstallBtn.href}`);
        }

        
    } catch (error) {
        console.error('Error loading builds:', error);
        buildsContainer.innerHTML = `
            <div class="error">
                Error loading builds: ${error.message}<br>
                <small>Make sure builds.json exists and is accessible.</small>
            </div>
        `;
    }
}

// Load builds when page loads
document.addEventListener('DOMContentLoaded', loadBuilds);

// Auto-refresh every 30 seconds to show new builds
setInterval(loadBuilds, 30000);
