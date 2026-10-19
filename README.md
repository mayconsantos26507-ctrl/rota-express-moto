# Rota Express Moto — MVP Android

Aplicativo Flutter inicial para importar PDF exportado pelo Spoke/Shopee, extrair códigos e endereços, localizar as paradas, numerar a sequência e mostrar mapa/traçado de ruas.

## O que já está no protótipo
- Seleção de PDF no Android.
- Extração de texto do PDF e tentativa de leitura de códigos `BR...` e endereço nas notas do Spoke.
- Campo para escolher manualmente o ponto de partida em cada rota.
- Geocodificação dos endereços com o serviço de geocodificação do dispositivo.
- Ordenação inicial por vizinho geográfico mais próximo.
- Mapa OpenStreetMap com paradas numeradas e traçado viário OSRM quando disponível.
- Botão para abrir navegação para uma parada no Google Maps.

## Limitações importantes do MVP
- **A ordem ainda é uma heurística por distância em linha reta**, não uma otimização profissional por tempo/distância viária. Para produção, implementar matriz de tempos de viagem para moto e algoritmo de otimização (ex.: OSRM/GraphHopper/Google Routes com serviço e limites adequados).
- A disponibilidade e precisão do geocodificador Android variam por aparelho e conexão. Endereços não localizados ficam no fim para revisão.
- O serviço público de demonstração OSRM/OpenStreetMap não oferece SLA de produção; configurar provedor próprio ou API contratada antes de publicar amplamente.
- A navegação externa abre Google Maps em modo de direção; o modo moto não é suportado de forma uniforme em todas as regiões/URLs.
- O parser foi iniciado a partir de um PDF exportado pelo Spoke. PDFs escaneados, layouts diferentes ou PDFs protegidos podem exigir OCR e ajustes. Sempre revisar os endereços antes de sair.
- O número sequencial é a ordem de entrega; o código `BR...` continua associado ao endereço para identificar o pacote.

## Como executar
1. Instale Flutter SDK e Android Studio.
2. Extraia o ZIP e entre na pasta `rota_express_moto`.
3. Gere a estrutura nativa Android com `flutter create . --platforms=android`.
4. Execute `flutter pub get`.
5. Execute `flutter run` com um Android conectado ou emulador.
6. Para gerar APK de teste: `flutter build apk --debug`.

## Dependências e publicação
O projeto usa Syncfusion Flutter PDF para extração de texto. Verifique os termos/licença aplicáveis ao seu uso antes de distribuir comercialmente. Inclua permissões de Internet no AndroidManifest (Flutter normalmente já inclui configuração básica; confira o manifesto do projeto gerado).

## Próximos passos para produção
1. Validar o parser com vários PDFs reais de Spoke e Shopee.
2. Adicionar edição manual de endereços não reconhecidos e visualização dos códigos completos.
3. Usar matriz viária real e otimização de rota com limite de 100+ paradas.
4. Adicionar status entregue/pendente/ausente sem incrementar acidentalmente ao tocar na linha.
5. Exportar lista numerada e permitir busca por código de pacote.
6. Tratar privacidade: os PDFs podem conter dados pessoais; processar localmente sempre que possível e não manter arquivos além do necessário.
