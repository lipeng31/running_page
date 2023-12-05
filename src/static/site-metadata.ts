interface ISiteMetadataResult {
  siteTitle: string;
  siteUrl: string;
  description: string;
  logo: string;
  navLinks: {
    name: string;
    url: string;
  }[];
}

const data: ISiteMetadataResult = {
  siteTitle: 'Li Peng\'s Running Page',
  siteUrl: 'https://lipeng31.github.io/running_page/',
  logo: 'https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcQTtc69JxHNcmN1ETpMUX4dozAgAN6iPjWalQ&usqp=CAU',
  description: 'My running statistics. Thanks to [Yi Hong](https://github.com/yihong0618) for developing this amazing project.',
  navLinks: [
    {
      name: 'Blog',
      url: 'https://lipeng31.github.io',
    },
    {
      name: 'About',
      url: 'https://lipeng31.github.io/about.html',
    },
  ],
};

export default data;
