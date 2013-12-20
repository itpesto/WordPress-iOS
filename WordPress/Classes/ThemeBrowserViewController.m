/*
 * ThemeBrowserViewController.m
 *
 * Copyright (c) 2013 WordPress. All rights reserved.
 *
 * Licensed under GNU General Public License 2.0.
 * Some rights reserved. See license.txt
 */

#import "ThemeBrowserViewController.h"
#import "Theme.h"
#import "ContextManager.h"
#import "ThemeBrowserCell.h"
#import "ThemeDetailsViewController.h"
#import "Blog.h"
#import "WPStyleGuide.h"
#import "WPNoResultsView.h"

static NSString *const ThemeCellIdentifier = @"theme";
static NSString *const SearchFilterCellIdentifier = @"search_filter";

@interface ThemeBrowserViewController () <UICollectionViewDelegate, UICollectionViewDataSource, NSFetchedResultsControllerDelegate, UIActionSheetDelegate, UISearchBarDelegate>

@property (weak, nonatomic) IBOutlet UICollectionView *collectionView;
@property (weak, nonatomic) IBOutlet UISearchBar *searchBar;
@property (nonatomic, weak) WPNoResultsView *noThemesView;
@property (nonatomic, weak) UIRefreshControl *refreshHeaderView;
@property (nonatomic, strong) NSArray *sortingOptions, *resultSortAttributes;
@property (nonatomic, strong) NSString *currentResultsSort, *currentSearchText;
@property (nonatomic, strong) NSArray *allThemes, *filteredThemes;
@property (nonatomic, strong) Theme *currentTheme;
@property (nonatomic, strong) NSFetchedResultsController *resultsController;

@end

@implementation ThemeBrowserViewController

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil {
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        self.title = NSLocalizedString(@"Themes", @"Title for Themes browser");
        _currentResultsSort = @"trendingRank";
        _resultSortAttributes = @[@"trendingRank", @"launchDate", @"popularityRank"];
        _sortingOptions = @[NSLocalizedString(@"Trending", @"Theme filter"),
                            NSLocalizedString(@"Newest", @"Theme filter"),
                            NSLocalizedString(@"Popular", @"Theme filter")];
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    self.collectionView.dataSource = self;
    self.collectionView.delegate = self;
    [WPStyleGuide configureColorsForView:self.view collectionView:self.collectionView];
    [self.collectionView registerClass:[ThemeBrowserCell class] forCellWithReuseIdentifier:ThemeCellIdentifier];
    
    [self.collectionView addSubview:self.searchBar];
    self.searchBar.delegate = self;
    
    UIRefreshControl *refreshHeaderView = [[UIRefreshControl alloc] initWithFrame:CGRectMake(0.0f, 0.0f - self.collectionView.bounds.size.height, self.collectionView.frame.size.width, self.collectionView.bounds.size.height)];
    _refreshHeaderView = refreshHeaderView;
    [_refreshHeaderView addTarget:self action:@selector(refreshControlTriggered:) forControlEvents:UIControlEventValueChanged];
    _refreshHeaderView.tintColor = [WPStyleGuide whisperGrey];
    [self.collectionView addSubview:_refreshHeaderView];
    
    UIBarButtonItem *sortButton = [[UIBarButtonItem alloc] initWithTitle:_sortingOptions[0] style:UIBarButtonItemStylePlain target:self action:@selector(sortPressed)];
    self.navigationItem.rightBarButtonItem = sortButton;
    
    [self syncThemesAndCurrentTheme];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];

    if (![_currentTheme.themeId isEqualToString:self.blog.currentThemeId]) {
        [self currentThemeForBlog];
        self.filteredThemes = _allThemes;
        [self applyFilterWithSearchText:_currentSearchText];
    }
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    
    self.allThemes = nil;
    self.filteredThemes = nil;
}

- (NSFetchedResultsController *)resultsController {
    if (!_resultsController) {
        NSManagedObjectContext *context = [[ContextManager sharedInstance] mainContext];
        NSFetchRequest *fetchRequest = [NSFetchRequest fetchRequestWithEntityName:NSStringFromClass([Theme class])];
        fetchRequest.predicate = [NSPredicate predicateWithFormat:@"blog == %@", self.blog];
        fetchRequest.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:_currentResultsSort ascending:YES]];
        fetchRequest.fetchBatchSize = 10;
        _resultsController = [[NSFetchedResultsController alloc] initWithFetchRequest:fetchRequest managedObjectContext:context sectionNameKeyPath:nil cacheName:nil];
        _resultsController.delegate = self;
        [_resultsController performFetch:nil];
        _allThemes = self.filteredThemes = _resultsController.fetchedObjects;
    }
    
    return _resultsController;
}

- (void)currentThemeForBlog {
    NSArray *currentThemeResults = [_allThemes filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"self.themeId == %@", self.blog.currentThemeId]];
    if (currentThemeResults.count) {
        _currentTheme = currentThemeResults[0];
    } else {
        _currentTheme = nil;
    }
}

- (void)syncThemesAndCurrentTheme {
    [Theme fetchAndInsertThemesForBlog:self.blog success:^{
        [Theme fetchCurrentThemeForBlog:self.blog success:^{
            [self currentThemeForBlog];
            [_refreshHeaderView endRefreshing];
        } failure:^(NSError *error) {
            [WPError showNetworkingAlertWithError:error];
            [_refreshHeaderView endRefreshing];
        }];
    } failure:^(NSError *error) {
        [WPError showNetworkingAlertWithError:error];
        [_refreshHeaderView endRefreshing];
    }];
}

- (void)toggleNoThemesView:(BOOL)show {
    if (!show) {
        _noThemesView.hidden = YES;
        return;
    }
    if (!_noThemesView) {
        _noThemesView = [WPNoResultsView noResultsViewWithTitle:NSLocalizedString(@"No themes to display", nil) message:nil accessoryView:nil buttonTitle:nil];
        [self.collectionView addSubview:_noThemesView];
    }
    _noThemesView.hidden = NO;
}

- (void)removeCurrentThemeFromList {
    _filteredThemes = [_filteredThemes filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"self != %@", _currentTheme]];
}

#pragma mark - UICollectionViewDelegate/DataSource

- (NSInteger)numberOfSectionsInCollectionView:(UICollectionView *)collectionView {
    return [self.resultsController sections].count;
}

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return _filteredThemes.count + (_currentTheme ? 1 : 0);
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.item == 0 && _currentTheme) {
        ThemeBrowserCell *current = [collectionView dequeueReusableCellWithReuseIdentifier:ThemeCellIdentifier forIndexPath:indexPath];
        current.theme = _currentTheme;
        return current;
    }
    
    ThemeBrowserCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:ThemeCellIdentifier forIndexPath:indexPath];
    NSUInteger index = _currentTheme ? indexPath.item - 1 : indexPath.item;
    Theme *theme = self.filteredThemes[index];
    cell.theme = theme;
    return cell;
}

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    Theme *theme;
    if (indexPath.item == 0 && _currentTheme) {
        theme = _currentTheme;
    } else {
        NSUInteger index = _currentTheme ? indexPath.item - 1 : indexPath.item;
        theme = self.filteredThemes[index];
    }
    
    ThemeDetailsViewController *details = [[ThemeDetailsViewController alloc] initWithTheme:theme];
    [self.navigationController pushViewController:details animated:YES];
}

#pragma mark - Collection view flow layout

- (CGSize)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)collectionViewLayout sizeForItemAtIndexPath:(NSIndexPath *)indexPath { 
    return IS_IPAD ? CGSizeMake(300, 255) : CGSizeMake(272, 234);
}

- (CGFloat)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)collectionViewLayout minimumInteritemSpacingForSectionAtIndex:(NSInteger)section {
    return IS_IPAD ? 20.0f : 7.0f;
}

- (CGFloat)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)collectionViewLayout minimumLineSpacingForSectionAtIndex:(NSInteger)section {
    return IS_IPAD ? 25.0f : 10.0f;
}

- (UIEdgeInsets)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)collectionViewLayout insetForSectionAtIndex:(NSInteger)section {
    CGFloat iPadInset = UIInterfaceOrientationIsLandscape([[UIApplication sharedApplication] statusBarOrientation]) ? 35.0f : 70.0f;
    return IS_IPAD ? UIEdgeInsetsMake(30, iPadInset, 30, iPadInset) : UIEdgeInsetsMake(7, 7, 7, 7);
}

- (void)didRotateFromInterfaceOrientation:(UIInterfaceOrientation)fromInterfaceOrientation {
    [self.collectionView performBatchUpdates:nil completion:nil];
    [super didRotateFromInterfaceOrientation:fromInterfaceOrientation];
}

#pragma mark - FetchedResultsController

- (void)controllerDidChangeContent:(NSFetchedResultsController *)controller {
    _allThemes = self.filteredThemes = controller.fetchedObjects;
    [self currentThemeForBlog];
}

#pragma mark - Setters

- (void)setFilteredThemes:(NSArray *)filteredThemes {
    _filteredThemes = filteredThemes;
    
    [self toggleNoThemesView:(_filteredThemes.count == 0 && !_currentTheme)];
    
    [self removeCurrentThemeFromList];
    [self applyCurrentSort];
}

- (void)applyCurrentSort {
    NSString *key = [@"self." stringByAppendingString:_currentResultsSort];
    BOOL ascending = ![_currentResultsSort isEqualToString:_resultSortAttributes[1]];
    _filteredThemes = [_filteredThemes sortedArrayUsingDescriptors:@[[NSSortDescriptor sortDescriptorWithKey:key ascending:ascending]]];
    [self.collectionView reloadData];
}

- (void)sortPressed {
    UIActionSheet *actionSheet = [[UIActionSheet alloc] initWithTitle:NSLocalizedString(@"Order By", nil) delegate:self cancelButtonTitle:NSLocalizedString(@"Cancel", nil) destructiveButtonTitle:nil otherButtonTitles:
                                  _sortingOptions[0],
                                  _sortingOptions[1],
                                  _sortingOptions[2],
                                  nil];
    [actionSheet showFromBarButtonItem:self.navigationItem.rightBarButtonItem animated:YES];
}

- (void)selectedSortIndex:(NSUInteger)sortIndex {
    _currentResultsSort = _resultSortAttributes[sortIndex];
    [self applyCurrentSort];
}

- (void)applyFilterWithSearchText:(NSString *)searchText {
    if (!searchText || searchText.length == 0) {
        [self clearSearchFilter];
        return;
    }
    self.filteredThemes = [_allThemes filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"self.themeId CONTAINS[cd] %@", searchText]];
    _currentSearchText = searchText;
}

- (void)clearSearchFilter {
    self.filteredThemes = _allThemes;
    _currentSearchText = nil;
}


#pragma mark - UISearchBarDelegate

- (void)searchBarTextDidBeginEditing:(UISearchBar *)searchBar {
    [searchBar setShowsCancelButton:YES animated:YES];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
    [self applyFilterWithSearchText:searchBar.text];
    [searchBar setShowsCancelButton:(searchBar.text.length > 0) animated:YES];
}

- (void)searchBarTextDidEndEditing:(UISearchBar *)searchBar {
    if (searchBar.text.length == 0) {
        [searchBar setShowsCancelButton:NO animated:YES];
        [self clearSearchFilter];
    }
}

- (void)searchBarCancelButtonClicked:(UISearchBar *)searchBar {
    [self clearSearchFilter];
    searchBar.text = nil;
    [searchBar setShowsCancelButton:NO animated:YES];
}


#pragma mark - UIRefreshControl

- (void)refreshControlTriggered:(UIRefreshControl*)refreshControl {
    if (refreshControl.isRefreshing) {
        [self syncThemesAndCurrentTheme];
    }
}


#pragma mark - UIActionSheetDelegate

- (void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex {
    if (buttonIndex < _sortingOptions.count) {
        [self.navigationItem.rightBarButtonItem setTitle:[actionSheet buttonTitleAtIndex:buttonIndex]];
        [self selectedSortIndex:buttonIndex];
    }
}

@end
