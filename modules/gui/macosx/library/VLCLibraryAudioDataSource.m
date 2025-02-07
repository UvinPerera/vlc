/*****************************************************************************
 * VLCLibraryAudioDataSource.m: MacOS X interface module
 *****************************************************************************
 * Copyright (C) 2019 VLC authors and VideoLAN
 *
 * Authors: Felix Paul Kühne <fkuehne # videolan -dot- org>
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston MA 02110-1301, USA.
 *****************************************************************************/

#import "VLCLibraryAudioDataSource.h"

#import "main/VLCMain.h"

#import "library/VLCLibraryModel.h"
#import "library/VLCLibraryController.h"
#import "library/VLCLibraryDataTypes.h"
#import "library/VLCLibraryTableCellView.h"
#import "library/VLCLibraryAlbumTableCellView.h"
#import "library/VLCLibraryCollectionViewItem.h"
#import "library/VLCLibraryCollectionViewFlowLayout.h"
#import "library/VLCLibraryCollectionViewAlbumSupplementaryDetailView.h"

#import "extensions/NSString+Helpers.h"
#import "views/VLCImageView.h"

@interface VLCLibraryAudioDataSource () <NSCollectionViewDelegate, NSCollectionViewDataSource>
{
    VLCLibraryCollectionViewFlowLayout *_collectionViewFlowLayout;
    NSInteger _currentSelectedSegment;
    NSArray<NSString *> *_placeholderImageNames;
    NSArray<NSString *> *_placeholderLabelStrings;
    NSArray *_displayedCollection;
    enum vlc_ml_parent_type _currentParentType;
}
@end

@implementation VLCLibraryAudioDataSource

- (instancetype)init
{
    self = [super init];
    return self;
}

- (void)setupAppearance
{
    NSArray *availableCollections = [VLCLibraryModel availableAudioCollections];
    NSUInteger availableCollectionsCount = availableCollections.count;
    self.segmentedControl.segmentCount = availableCollectionsCount;
    for (NSUInteger x = 0; x < availableCollectionsCount; x++) {
        [self.segmentedControl setLabel:availableCollections[x] forSegment:x];
    }

    _collectionView.dataSource = self;
    _collectionView.delegate = self;

    [_collectionView registerClass:[VLCLibraryCollectionViewItem class] forItemWithIdentifier:VLCLibraryCellIdentifier];

    NSNib *albumSupplementaryDetailView = [[NSNib alloc] initWithNibNamed:@"VLCLibraryCollectionViewAlbumSupplementaryDetailView" bundle:nil];
    [_collectionView registerNib:albumSupplementaryDetailView
      forSupplementaryViewOfKind:VLCLibraryCollectionViewAlbumSupplementaryDetailViewKind 
                  withIdentifier:VLCLibraryCollectionViewAlbumSupplementaryDetailViewIdentifier];

    _collectionViewFlowLayout = [[VLCLibraryCollectionViewFlowLayout alloc] init];
    _collectionView.collectionViewLayout = _collectionViewFlowLayout;

    _groupSelectionTableView.target = self;
    _groupSelectionTableView.doubleAction = @selector(groubSelectionDoubleClickAction:);
    _collectionSelectionTableView.target = self;
    _collectionSelectionTableView.doubleAction = @selector(collectionSelectionDoubleClickAction:);
    
    _currentSelectedSegment = _segmentedControl.indexOfSelectedItem;
    _placeholderImageNames = @[@"placeholder-group2", @"placeholder-music", @"placeholder-music", @"placeholder-music"];
    _placeholderLabelStrings = @[
        _NS("Your favorite artists will appear here.\nGo to the Browse section to add artists you love."),
        _NS("Your favorite albums will appear here.\nGo to the Browse section to add albums you love."),
        _NS("Your favorite tracks will appear here.\nGo to the Browse section to add tracks you love."),
        _NS("Your favorite genres will appear here.\nGo to the Browse section to add genres you love."),
    ];

    [self reloadAppearance];
    [self reloadEmptyViewAppearance];
}

- (void)reloadAppearance
{
    [self.segmentedControl setTarget:self];
    [self.segmentedControl setAction:@selector(segmentedControlAction:)];
    [self segmentedControlAction:nil];

    [self.collectionSelectionTableView reloadData];
    [self.groupSelectionTableView reloadData];

    [self.collectionView reloadData];
}

- (void)reloadEmptyViewAppearance
{
    _placeholderImageView.image = [NSImage imageNamed:_placeholderImageNames[_currentSelectedSegment]];
    _placeholderLabel.stringValue = _placeholderLabelStrings[_currentSelectedSegment];
}

- (IBAction)segmentedControlAction:(id)sender
{
    enum vlc_ml_parent_type oldParentType = _currentParentType;

    _currentSelectedSegment = _segmentedControl.selectedSegment;
    switch (_currentSelectedSegment) {
        case 0:
            _displayedCollection = [self.libraryModel listOfArtists];
            _currentParentType = VLC_ML_PARENT_ARTIST;
            break;
        case 1:
            _displayedCollection = [self.libraryModel listOfAlbums];
            _currentParentType = VLC_ML_PARENT_ALBUM;
            break;
        case 2:
            _displayedCollection = [self.libraryModel listOfAudioMedia];
            _currentParentType = VLC_ML_PARENT_UNKNOWN;
            break;
        case 3:
            _displayedCollection = [self.libraryModel listOfGenres];
            _currentParentType = VLC_ML_PARENT_GENRE;
            break;

        default:
            NSAssert(1, @"reached the unreachable");
            break;
    }
    
    if (_libraryModel.listOfAudioMedia.count == 0) {
        [self reloadEmptyViewAppearance];
        return;
    }

    if(oldParentType == _currentParentType) {
        return;
    }

    [_collectionViewFlowLayout resetLayout];
    
    [self.collectionView reloadData];
    [self.collectionSelectionTableView reloadData];
    [self.groupSelectionTableView reloadData];
}

- (NSString *)imageNameForCurrentSegment
{
    return _placeholderImageNames[_currentSelectedSegment];
}

#pragma mark - table view data source and delegation

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
    return _displayedCollection.count;
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
    VLCLibraryTableCellView *cellView = [tableView makeViewWithIdentifier:VLCAudioLibraryCellIdentifier owner:self];

    if (cellView == nil) {
        /* the following code saves us an instance of NSViewController which we don't need */
        NSNib *nib = [[NSNib alloc] initWithNibNamed:@"VLCLibraryTableCellView" bundle:nil];
        NSArray *topLevelObjects;
        if (![nib instantiateWithOwner:self topLevelObjects:&topLevelObjects]) {
            NSAssert(1, @"Failed to load nib file to show audio library items");
            return nil;
        }

        for (id topLevelObject in topLevelObjects) {
            if ([topLevelObject isKindOfClass:[VLCLibraryTableCellView class]]) {
                cellView = topLevelObject;
                break;
            }
        }
        cellView.identifier = VLCAudioLibraryCellIdentifier;
    }

    switch (_currentParentType) {
        case VLC_ML_PARENT_ARTIST:
        {
            VLCMediaLibraryArtist *artist = _displayedCollection[row];

            cellView.singlePrimaryTitleTextField.hidden = NO;
            cellView.singlePrimaryTitleTextField.stringValue = artist.name;
            cellView.representedImageView.image = artist.smallArtworkImage;
            break;
        }
        case VLC_ML_PARENT_ALBUM:
        {
            VLCMediaLibraryAlbum *album = _displayedCollection[row];

            cellView.primaryTitleTextField.hidden = NO;
            cellView.secondaryTitleTextField.hidden = NO;
            cellView.primaryTitleTextField.stringValue = album.title;
            cellView.secondaryTitleTextField.stringValue = album.artistName;
            cellView.representedImageView.image = album.smallArtworkImage;
            break;
        }
        case VLC_ML_PARENT_UNKNOWN:
        {
            VLCMediaLibraryMediaItem *mediaItem = _displayedCollection[row];

            cellView.representedImageView.image = mediaItem.smallArtworkImage;
            cellView.representedMediaItem = mediaItem;

            NSString *title = mediaItem.title;
            NSString *nameOfArtist;

            VLCMediaLibraryArtist *artist = [VLCMediaLibraryArtist artistWithID:mediaItem.artistID];
            if (artist) {
                nameOfArtist = artist.name;
            }

            if (title && nameOfArtist) {
                cellView.primaryTitleTextField.hidden = NO;
                cellView.secondaryTitleTextField.hidden = NO;
                cellView.primaryTitleTextField.stringValue = title;
                cellView.secondaryTitleTextField.stringValue = nameOfArtist;
            } else {
                cellView.singlePrimaryTitleTextField.hidden = NO;
                cellView.singlePrimaryTitleTextField.stringValue = title;
            }
            break;
        }
        case VLC_ML_PARENT_GENRE:
        {
            VLCMediaLibraryGenre *genre = _displayedCollection[row];

            cellView.primaryTitleTextField.hidden = NO;
            cellView.secondaryTitleTextField.hidden = NO;
            cellView.primaryTitleTextField.stringValue = genre.name;
            cellView.secondaryTitleTextField.stringValue = [NSString stringWithFormat:_NS("%lli items"), genre.numberOfTracks];
            cellView.representedImageView.image = genre.smallArtworkImage;
            break;
        }
        default:
            NSAssert(1, @"reached the unreachable");
            break;
    }

    return cellView;
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification
{
    switch (_currentParentType) {
        case VLC_ML_PARENT_ARTIST:
        {
            VLCMediaLibraryArtist *artist = _displayedCollection[self.collectionSelectionTableView.selectedRow];
            NSArray *albumsForArtist = [_libraryModel listAlbumsOfParentType:VLC_ML_PARENT_ARTIST forID:artist.artistID];
            _groupDataSource.representedListOfAlbums = albumsForArtist;
            break;
        }
        case VLC_ML_PARENT_ALBUM:
        {
            VLCMediaLibraryAlbum *album = _displayedCollection[self.collectionSelectionTableView.selectedRow];
            _groupDataSource.representedListOfAlbums = @[album];
            break;
        }
        case VLC_ML_PARENT_UNKNOWN:
        {
            // FIXME: we have nothing to show here
            _groupDataSource.representedListOfAlbums = nil;
            break;
        }
        case VLC_ML_PARENT_GENRE:
        {
            VLCMediaLibraryGenre *genre = _displayedCollection[self.collectionSelectionTableView.selectedRow];
            NSArray *albumsForGenre = [_libraryModel listAlbumsOfParentType:VLC_ML_PARENT_GENRE forID:genre.genreID];
            _groupDataSource.representedListOfAlbums = albumsForGenre;
            break;
        }
        default:
            NSAssert(1, @"reached the unreachable");
            break;
    }

    [self.groupSelectionTableView reloadData];
}

#pragma mark - table view double click actions

- (void)groubSelectionDoubleClickAction:(id)sender
{
    NSArray *listOfAlbums = _groupDataSource.representedListOfAlbums;
    NSUInteger albumCount = listOfAlbums.count;
    if (!listOfAlbums || albumCount == 0) {
        return;
    }

    NSInteger clickedRow = _groupSelectionTableView.clickedRow;
    if (clickedRow > albumCount) {
        return;
    }

    VLCLibraryController *libraryController = [[VLCMain sharedInstance] libraryController];

    NSArray *tracks = [listOfAlbums[clickedRow] tracksAsMediaItems];
    [libraryController appendItemsToPlaylist:tracks playFirstItemImmediately:YES];
}

- (void)collectionSelectionDoubleClickAction:(id)sender
{
    NSArray <VLCMediaLibraryAlbum *> *listOfAlbums = nil;

    switch (_currentParentType) {
        case VLC_ML_PARENT_ARTIST:
        {
            VLCMediaLibraryArtist *artist = _displayedCollection[self.collectionSelectionTableView.selectedRow];
            listOfAlbums = [_libraryModel listAlbumsOfParentType:VLC_ML_PARENT_ARTIST forID:artist.artistID];
            break;
        }
        case VLC_ML_PARENT_ALBUM:
        {
            VLCMediaLibraryAlbum *album = _displayedCollection[self.collectionSelectionTableView.selectedRow];
            listOfAlbums = @[album];
            break;
        }
        case VLC_ML_PARENT_UNKNOWN:
        {
            // FIXME: we have nothing to show here
            listOfAlbums = nil;
            break;
        }
        case VLC_ML_PARENT_GENRE:
        {
            VLCMediaLibraryGenre *genre = _displayedCollection[self.collectionSelectionTableView.selectedRow];
            listOfAlbums = [_libraryModel listAlbumsOfParentType:VLC_ML_PARENT_GENRE forID:genre.genreID];
            break;
        }
        default:
            NSAssert(1, @"reached the unreachable");
            break;
    }

    if (listOfAlbums.count == 0) {
        return;
    }

    VLCLibraryController *libraryController = [[VLCMain sharedInstance] libraryController];
    for (VLCMediaLibraryAlbum *album in listOfAlbums) {
        NSArray *tracks = [album tracksAsMediaItems];
        [libraryController appendItemsToPlaylist:tracks playFirstItemImmediately:YES];
    }
}

#pragma mark - collection view data source and delegation

- (NSInteger)collectionView:(NSCollectionView *)collectionView
     numberOfItemsInSection:(NSInteger)section
{
    return _displayedCollection.count;
}

- (NSInteger)numberOfSectionsInCollectionView:(NSCollectionView *)collectionView
{
    return 1;
}

- (NSCollectionViewItem *)collectionView:(NSCollectionView *)collectionView
     itemForRepresentedObjectAtIndexPath:(NSIndexPath *)indexPath
{
    VLCLibraryCollectionViewItem *viewItem = [collectionView makeItemWithIdentifier:VLCLibraryCellIdentifier forIndexPath:indexPath];

    switch (_currentParentType) {
        case VLC_ML_PARENT_ARTIST:
        {
            VLCMediaLibraryArtist *artist = _displayedCollection[indexPath.item];
            viewItem.representedItem = artist;
            break;
        }
        case VLC_ML_PARENT_ALBUM:
        {
            VLCMediaLibraryAlbum *album = _displayedCollection[indexPath.item];
            viewItem.representedItem = album;
            break;
        }
        case VLC_ML_PARENT_UNKNOWN:
        {
            VLCMediaLibraryMediaItem *mediaItem = _displayedCollection[indexPath.item];
            viewItem.representedItem = mediaItem;
            break;
        }
        case VLC_ML_PARENT_GENRE:
        {
            VLCMediaLibraryGenre *genre = _displayedCollection[indexPath.item];
            viewItem.representedItem = genre;
            break;
        }
        default:
            break;
    }

    return viewItem;
}

- (void)collectionView:(NSCollectionView *)collectionView didSelectItemsAtIndexPaths:(NSSet<NSIndexPath *> *)indexPaths
{
    NSIndexPath *indexPath = indexPaths.anyObject;
    if (!indexPath || _currentParentType != VLC_ML_PARENT_ALBUM) {
        return;
    }

    [_collectionViewFlowLayout expandDetailSectionAtIndex:indexPath];
}

- (void)collectionView:(NSCollectionView *)collectionView didDeselectItemsAtIndexPaths:(NSSet<NSIndexPath *> *)indexPaths
{
    NSIndexPath *indexPath = indexPaths.anyObject;
    if (!indexPath || _currentParentType != VLC_ML_PARENT_ALBUM) {
        return;
    }

    [_collectionViewFlowLayout collapseDetailSectionAtIndex:indexPath];
}

- (NSView *)collectionView:(NSCollectionView *)collectionView
viewForSupplementaryElementOfKind:(NSCollectionViewSupplementaryElementKind)kind
               atIndexPath:(NSIndexPath *)indexPath
{
    if ([kind isEqualToString:VLCLibraryCollectionViewAlbumSupplementaryDetailViewKind] && _currentParentType == VLC_ML_PARENT_ALBUM) {
        VLCLibraryCollectionViewAlbumSupplementaryDetailView* albumSupplementaryDetailView = [collectionView makeSupplementaryViewOfKind:kind withIdentifier:VLCLibraryCollectionViewAlbumSupplementaryDetailViewKind forIndexPath:indexPath];

        VLCMediaLibraryAlbum *album = _displayedCollection[indexPath.item];
        albumSupplementaryDetailView.representedAlbum = album;

        return albumSupplementaryDetailView;
    }

    return nil;
}

@end

@implementation VLCLibraryGroupDataSource

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
    if (_representedListOfAlbums != nil) {
        return _representedListOfAlbums.count;
    }

    return 0;
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
    VLCLibraryAlbumTableCellView *cellView = [tableView makeViewWithIdentifier:VLCAudioLibraryCellIdentifier owner:self];

    if (cellView == nil) {
        /* the following code saves us an instance of NSViewController which we don't need */
        NSNib *nib = [[NSNib alloc] initWithNibNamed:@"VLCLibraryAlbumTableCellView" bundle:nil];
        NSArray *topLevelObjects;
        if (![nib instantiateWithOwner:self topLevelObjects:&topLevelObjects]) {
            NSAssert(1, @"Failed to load nib file to show audio library items");
            return nil;
        }

        for (id topLevelObject in topLevelObjects) {
            if ([topLevelObject isKindOfClass:[VLCLibraryAlbumTableCellView class]]) {
                cellView = topLevelObject;
                break;
            }
        }
        cellView.identifier = VLCAudioLibraryCellIdentifier;
    }

    VLCMediaLibraryAlbum *album = _representedListOfAlbums[row];
    cellView.representedAlbum = album;

    return cellView;
}

- (CGFloat)tableView:(NSTableView *)tableView heightOfRow:(NSInteger)row
{
    VLCMediaLibraryAlbum *album = _representedListOfAlbums[row];
    if (!album) {
        return -1;
    }
    return [VLCLibraryAlbumTableCellView heightForAlbum:album];
}

@end
