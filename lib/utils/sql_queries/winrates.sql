WITH tmp as (
    SELECT
        C.name,
        C.colors,
        CAST(SUBSTRING(D.win_loss, 1, 1) as double) as wins,
        CAST(SUBSTRING(D.win_loss, 3, 1) as double) as losses,
        D.win_loss
    FROM decks D
    INNER JOIN decklists DL on D.id = DL.deck_id
    INNER JOIN cards C on DL.scryfall_id = C.scryfall_id
    WHERE D.cubecobra_id = '3f05b561-c5f0-40fd-a67c-76fe14905b1c'
        AND C.name NOT IN ('Plains', 'Island', 'Swamp', 'Mountain', 'Forest')
)
SELECT
    name,
    count(*) as num_decks,
    ROUND(SUM(wins) / SUM(wins + losses),2) as winrate
FROM tmp
GROUP BY name
ORDER BY winrate DESC