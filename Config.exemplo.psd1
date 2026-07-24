@{
    # ======================================================================
    # WinDebloat - Arquivo de configuração de EXEMPLO
    #
    # Como usar:
    #   1. Copie este arquivo e renomeie a cópia para:  Config.psd1
    #   2. Deixe-o na MESMA pasta do Core.ps1
    #   3. Edite as listas abaixo com o que você quer manter
    #   4. Rode a Simulação para conferir (os itens aparecem como PRESERVADO)
    #
    # O arquivo é opcional: sem ele, as listas padrão são usadas.
    # Formato: apenas dados (nenhum código é executado). Linhas iniciadas
    # por # são comentários. Para preservar um item, remova o # da linha.
    # ======================================================================

    # ----------------------------------------------------------------------
    # Aplicativos que você QUER MANTER (não serão removidos).
    # Use exatamente os nomes abaixo (a lista completa de alvos do projeto):
    #
    #   'Xbox App'              'Xbox Game Bar'         'Xbox Gaming Services'
    #   'Xbox Identity Provider' 'Xbox TCUI'            'Xbox Speech To Text'
    #   'Clipchamp'             'Teams Consumer'        'Skype'
    #   'Mixed Reality Portal'  '3D Viewer'             'Paint 3D'
    #   'Cortana'               'Feedback Hub'          'Get Help'
    #   'Quick Assist'          'Windows Maps'          'Bing News'
    #   'Bing Weather'          'Bing Sports'           'Bing Finance'
    #   'People'                'Phone Link / Your Phone'
    #   'Solitaire'             'To Do'                 'Office Hub'
    #   'OneConnect'            'Family'                'Alarms'
    #   'Sound Recorder'        'Camera'                'Movies & TV'
    #   'Zune Music (Groove)'   'Dev Home'              'Power Automate'
    # ----------------------------------------------------------------------
    PreservarApps = @(
        # 'Camera'
        # 'Alarms'
        # 'Phone Link / Your Phone'
    )

    # ----------------------------------------------------------------------
    # Serviços que você QUER MANTER como estão (não serão ajustados).
    # Nomes válidos (os alvos de otimização do projeto):
    #
    #   'DiagTrack'        'dmwappushservice'  'MapsBroker'      'Fax'
    #   'RetailDemo'       'WMPNetworkSvc'     'RemoteRegistry'
    #   'XblAuthManager'   'XblGameSave'       'XboxNetApiSvc'
    #   'SysMain'          'WerSvc'            'lfsvc'
    #   'TrkWks'           'WalletService'
    # ----------------------------------------------------------------------
    PreservarServicos = @(
        # 'SysMain'
    )
}
