#import "RTMediaKeys.h"
#import <MediaPlayer/MediaPlayer.h>

@implementation RTMediaKeys

- (void)start
{
    MPRemoteCommandCenter *cc = [MPRemoteCommandCenter sharedCommandCenter];
    __weak typeof(self) weakSelf = self;
    [cc.togglePlayPauseCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *e) {
        [weakSelf.delegate mediaKeysTogglePlay];
        return MPRemoteCommandHandlerStatusSuccess;
    }];
    [cc.playCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *e) {
        [weakSelf.delegate mediaKeysPlay];
        return MPRemoteCommandHandlerStatusSuccess;
    }];
    [cc.pauseCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *e) {
        [weakSelf.delegate mediaKeysPause];
        return MPRemoteCommandHandlerStatusSuccess;
    }];
    [cc.stopCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *e) {
        [weakSelf.delegate mediaKeysPause];
        return MPRemoteCommandHandlerStatusSuccess;
    }];
    [cc.nextTrackCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *e) {
        [weakSelf.delegate mediaKeysNext];
        return MPRemoteCommandHandlerStatusSuccess;
    }];
    [cc.previousTrackCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *e) {
        [weakSelf.delegate mediaKeysPrevious];
        return MPRemoteCommandHandlerStatusSuccess;
    }];
    // una radio non si può mandare avanti o indietro nel tempo
    cc.seekForwardCommand.enabled = NO;
    cc.seekBackwardCommand.enabled = NO;
    cc.skipForwardCommand.enabled = NO;
    cc.skipBackwardCommand.enabled = NO;
    cc.changePlaybackPositionCommand.enabled = NO;
}

- (void)updateWithStation:(NSString *)station title:(NSString *)title artist:(NSString *)artist playing:(BOOL)playing
{
    MPNowPlayingInfoCenter *center = [MPNowPlayingInfoCenter defaultCenter];
    NSMutableDictionary *info = [NSMutableDictionary dictionary];
    info[MPMediaItemPropertyTitle] = title.length ? title : (station ?: @"RadioTray");
    if (artist.length) info[MPMediaItemPropertyArtist] = artist;
    if (station.length) info[MPMediaItemPropertyAlbumTitle] = station;
    info[MPNowPlayingInfoPropertyIsLiveStream] = @YES;
    info[MPNowPlayingInfoPropertyPlaybackRate] = playing ? @1.0 : @0.0;
    center.nowPlayingInfo = info;
    center.playbackState = playing ? MPNowPlayingPlaybackStatePlaying : MPNowPlayingPlaybackStatePaused;
}

@end
