// Handle install button clicks with debugging and user agent detection
function handleInstallClick(event, installUrl) {
    console.log('Install button clicked!');
    console.log(`Attempting to navigate to: ${installUrl}`);
    console.log(`User agent: ${navigator.userAgent}`);
    
    const isIOS = /iPad|iPhone|iPod/.test(navigator.userAgent);
    const isSafari = /Safari/.test(navigator.userAgent) && !/Chrome/.test(navigator.userAgent);
    
    console.log(`Is iOS device: ${isIOS}`);
    console.log(`Is Safari: ${isSafari}`);
    
    if (!isIOS) {
        event.preventDefault();
        alert('⚠️ iOS App Installation\n\nThis install link only works on iOS devices (iPhone/iPad) using Safari.\n\nTo install:\n1. Open this page on your iOS device\n2. Use Safari browser\n3. Click the Install button\n4. Follow the prompts to install the app');
        return false;
    }
    
    if (!isSafari) {
        event.preventDefault();
        alert('⚠️ Please use Safari\n\nApp installation requires Safari browser on iOS.\n\nPlease:\n1. Copy this page URL\n2. Open Safari\n3. Paste the URL and navigate here\n4. Click Install again');
        return false;
    }
    
    // Let the default link behavior happen for iOS Safari
    console.log('Proceeding with iOS Safari installation...');
    return true;
}

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
                    <a href="${installUrl}" class="install-btn" onclick="handleInstallClick(event, '${installUrl}')">Install</a>
                </div>
            `;
        }).join('');

        buildsContainer.innerHTML = buildsHtml;
        
        // Log the actual value of the install URL for debugging by querying the DOM
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
document.addEventListener('DOMContentLoaded', () => {
    // Check platform and show notice for non-iOS devices
    const isIOS = /iPad|iPhone|iPod/.test(navigator.userAgent);
    const platformNotice = document.getElementById('platform-notice');
    
    if (!isIOS && platformNotice) {
        platformNotice.style.display = 'block';
    }
    
    // Load builds
    loadBuilds();
});

// Auto-refresh every 30 seconds to show new builds
setInterval(loadBuilds, 30000);
