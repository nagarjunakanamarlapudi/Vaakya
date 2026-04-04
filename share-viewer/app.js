/* Vaakya Web Share Viewer */

const API_BASE = window.location.hostname === 'localhost'
    ? 'http://localhost:8000'
    : 'https://api.vaakya.app';

const token = window.location.pathname.split('/').filter(Boolean).pop();

const app = document.getElementById('app');

/* Speaker colors — consistent palette for up to 8 speakers */
const SPEAKER_COLORS = [
    '#34A853', '#4285F4', '#EA4335', '#FBBC04',
    '#9334E6', '#E91E63', '#00BCD4', '#FF5722'
];

/* Block type labels */
const BLOCK_LABELS = {
    summary: 'Summary',
    decision: 'Decision',
    action_item: 'Action Item',
    quote: 'Quote'
};

/* Block type sort order */
const BLOCK_ORDER = ['summary', 'decision', 'action_item', 'quote'];

/* Group heading text */
const GROUP_HEADINGS = {
    summary: 'Summary',
    decision: 'Decisions',
    action_item: 'Action Items',
    quote: 'Key Quotes'
};

/* Fetch and render */
if (token) {
    fetch(`${API_BASE}/share/${token}`)
        .then(function (r) {
            if (r.ok) return r.json();
            if (r.status === 404 || r.status === 410) throw { type: 'expired' };
            throw { type: 'error', status: r.status };
        })
        .then(function (data) {
            renderMeeting(data);
        })
        .catch(function (err) {
            if (err && err.type === 'expired') {
                renderExpired();
            } else {
                renderError();
            }
        });
} else {
    renderError();
}

/* --- Render functions --- */

function renderMeeting(data) {
    var meeting = data.meeting;
    var blocks = data.blocks || [];

    var html = '<div class="container">';

    /* Privacy badge */
    html += '<div class="privacy-badge">&#128274; Notes processed on-device</div>';

    /* Title */
    html += '<h1 class="meeting-title">' + escapeHtml(meeting.title) + '</h1>';

    /* Metadata bar */
    html += '<div class="metadata-bar">';
    if (meeting.started_at) {
        html += '<span class="metadata-item">' + formatDate(meeting.started_at) + '</span>';
        html += '<span class="metadata-separator"></span>';
    }
    if (meeting.duration_seconds) {
        html += '<span class="metadata-item">' + formatDuration(meeting.duration_seconds) + '</span>';
        html += '<span class="metadata-separator"></span>';
    }
    if (meeting.speaker_count) {
        html += '<span class="metadata-item">' + meeting.speaker_count + ' speaker' + (meeting.speaker_count !== 1 ? 's' : '') + '</span>';
        html += '<span class="metadata-separator"></span>';
    }
    if (meeting.source) {
        html += '<span class="source-tag">' + escapeHtml(meeting.source) + '</span>';
        html += '<span class="metadata-separator"></span>';
    }
    html += '<span class="shared-badge">Shared via Vaakya</span>';
    html += '</div>';

    /* Speaker breakdown */
    if (data.speakers && data.speakers.length > 0) {
        html += renderSpeakers(data.speakers);
    }

    /* Blocks grouped by type */
    var grouped = groupBlocks(blocks);
    for (var i = 0; i < BLOCK_ORDER.length; i++) {
        var type = BLOCK_ORDER[i];
        if (grouped[type] && grouped[type].length > 0) {
            html += '<div class="block-group">';
            html += '<h2 class="block-group-heading">' + GROUP_HEADINGS[type] + '</h2>';
            for (var j = 0; j < grouped[type].length; j++) {
                html += renderBlock(grouped[type][j]);
            }
            html += '</div>';
        }
    }

    /* Footer */
    html += renderFooter();

    html += '</div>';
    app.innerHTML = html;
}

function renderSpeakers(speakers) {
    var html = '<div class="speakers-section">';
    html += '<div class="speakers-heading">Speakers</div>';
    html += '<div class="speakers-list">';
    for (var i = 0; i < speakers.length; i++) {
        var speaker = speakers[i];
        var color = speaker.color || SPEAKER_COLORS[i % SPEAKER_COLORS.length];
        html += '<div class="speaker-chip">';
        html += '<span class="speaker-dot" style="background:' + color + '"></span>';
        html += '<span>' + escapeHtml(speaker.label || speaker.name || ('Speaker ' + (i + 1))) + '</span>';
        if (speaker.talk_time) {
            html += '<span class="speaker-time">' + speaker.talk_time + '</span>';
        }
        html += '</div>';
    }
    html += '</div>';
    html += '</div>';
    return html;
}

function renderBlock(block) {
    var type = block.type || 'summary';
    var html = '<div class="block block--' + type + '">';

    /* Header: badge + speaker */
    html += '<div class="block-header">';
    html += '<span class="block-badge block-badge--' + type + '">' + (BLOCK_LABELS[type] || type) + '</span>';
    if (block.speaker) {
        html += '<span class="block-speaker">' + escapeHtml(block.speaker) + '</span>';
    }
    html += '</div>';

    /* Content */
    if (type === 'action_item') {
        var checkedClass = block.is_checked ? ' action-checkbox--checked' : '';
        var contentClass = block.is_checked ? ' action-content--checked' : '';
        html += '<div class="action-item-row">';
        html += '<div class="action-checkbox' + checkedClass + '"></div>';
        html += '<div class="block-content' + contentClass + '">' + escapeHtml(block.content) + '</div>';
        html += '</div>';
    } else if (type === 'quote') {
        html += '<div class="block-content block-content--quote">"' + escapeHtml(block.content) + '"</div>';
    } else {
        html += '<div class="block-content">' + escapeHtml(block.content) + '</div>';
    }

    /* Meta text */
    if (block.meta_text) {
        html += '<div class="block-meta">' + escapeHtml(block.meta_text) + '</div>';
    }

    html += '</div>';
    return html;
}

function renderFooter() {
    var html = '<div class="footer">';
    html += '<a href="https://vaakya.app" class="cta-button" target="_blank" rel="noopener">Get Vaakya</a>';
    html += '<p class="footer-tagline">AI-powered meeting notes that never leave your device</p>';
    html += '</div>';
    return html;
}

function renderExpired() {
    var html = '<div class="state-message">';
    html += '<div class="state-icon">&#128279;</div>';
    html += '<h1 class="state-title">This link has expired</h1>';
    html += '<p class="state-subtitle">The person who shared these notes may be able to create a new link.</p>';
    html += '<a href="https://vaakya.app" class="cta-button" target="_blank" rel="noopener">Get Vaakya</a>';
    html += '<p class="footer-tagline" style="margin-top:12px">AI-powered meeting notes that never leave your device</p>';
    html += '</div>';
    app.innerHTML = html;
}

function renderError() {
    var html = '<div class="state-message">';
    html += '<div class="state-icon">&#9888;&#65039;</div>';
    html += '<h1 class="state-title">Something went wrong</h1>';
    html += '<p class="state-subtitle">Try refreshing the page.</p>';
    html += '</div>';
    app.innerHTML = html;
}

/* --- Helpers --- */

function groupBlocks(blocks) {
    var groups = {};
    for (var i = 0; i < blocks.length; i++) {
        var type = blocks[i].type || 'summary';
        if (!groups[type]) groups[type] = [];
        groups[type].push(blocks[i]);
    }
    return groups;
}

function formatDate(isoString) {
    try {
        var d = new Date(isoString);
        return d.toLocaleDateString('en-US', {
            weekday: 'short',
            month: 'short',
            day: 'numeric',
            year: 'numeric'
        });
    } catch (e) {
        return isoString;
    }
}

function formatDuration(seconds) {
    var h = Math.floor(seconds / 3600);
    var m = Math.floor((seconds % 3600) / 60);
    if (h > 0) {
        return h + 'h ' + m + 'm';
    }
    return m + ' min';
}

function escapeHtml(str) {
    if (!str) return '';
    var div = document.createElement('div');
    div.appendChild(document.createTextNode(str));
    return div.innerHTML;
}
